import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'webrtc_service.dart' show signalingServerUrl;

/// Küçük grup rastgele görüşmesi (mesh, 3-4 kişi) - Batch C'nin ertelenen
/// maddesi. WebRTCService (1:1 eşleştirme) ile KASITLI olarak AYRI bir
/// servis: veri modeli temelden farklı (tek partnerId/tek RTCPeerConnection
/// yerine, odadaki her diğer katılımcı için AYRI bir RTCPeerConnection).
///
/// SFU (merkezi medya sunucusu) DEĞİL - N kişilik bir odada her katılımcı
/// diğer N-1 kişiyle doğrudan bağlantı kurar (bkz. signaling_server/
/// server.js'deki aynı not). 4 kişide bu 6 eşzamanlı bağlantı demek.
///
/// Kamera/mikrofon EDİNME mantığını (getUserMedia, izin akışı) burada TEKRAR
/// YAZMIYORUZ - GroupCallPreScreen bunun için WebRTCService.initLocalMedia()
/// kullanır, buraya yalnızca hazır bir MediaStream referansı verilir. Bu
/// servis o akışın SAHİBİ değildir, kapatmaz - yalnızca her peer
/// connection'a track ekler.
class GroupCallPeer {
  final String socketId;
  final String? displayName;
  final bool verified;
  final String? photoUrl;
  RTCPeerConnection? pc;
  MediaStream? remoteStream;

  GroupCallPeer({
    required this.socketId,
    this.displayName,
    this.verified = false,
    this.photoUrl,
  });
}

class GroupCallService {
  io.Socket? _socket;
  MediaStream? _localStream;
  String? _roomId;
  bool _disposed = false;

  final Map<String, GroupCallPeer> _peers = {};
  // socketId -> pc kurulum Future'ı - hem 'group-call-matched' anında
  // proaktif olarak BAŞLATILIYOR hem de erken gelen bir 'signal' bunu
  // bulup bekleyebiliyor (bkz. _ensurePc notu). Bu, "offer'ı gönderen taraf
  // daha hızlı davranıp biz henüz pc kurmadan sinyal gönderdi" yarış
  // durumunu (race condition) çözüyor.
  final Map<String, Future<RTCPeerConnection>> _pcFutures = {};
  final Map<String, bool> _handlingOffer = {};
  final Map<String, bool> _handlingAnswer = {};

  List<GroupCallPeer> get peers => _peers.values.toList(growable: false);
  String? get roomId => _roomId;

  /// Katılımcı listesi VEYA herhangi bir uzak akış değiştiğinde tetiklenir -
  /// UI bunu görüp setState çağırmalı (ChangeNotifier kullanılmıyor, projenin
  /// geri kalanındaki basit callback deseniyle tutarlı olsun diye).
  void Function()? onUpdate;
  void Function(String status)? onStatusChange;
  void Function(String socketId)? onPeerLeft;
  void Function()? onCallEnded;
  void Function(String message)? onAccountRestricted;
  void Function(String reportId)? onReportSent;
  void Function(String message)? onReportError;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };
  Future<void>? _iceServersFuture;

  Future<void> _refreshIceServers() async {
    try {
      final response = await http
          .get(Uri.parse('$signalingServerUrl/turn-credentials'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final servers = data['iceServers'] as List<dynamic>?;
      if (servers == null || servers.isEmpty) return;
      _iceServers = {
        'iceServers':
            servers.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
      };
    } catch (_) {
      // Sessizce STUN-only ile devam - bkz. webrtc_service.dart'taki aynı not.
    }
  }

  /// [localStream] çağıran ekranın (GroupCallPreScreen) ZATEN başlattığı bir
  /// kamera/mikrofon akışı - burada YALNIZCA referans olarak tutulur, sahibi
  /// değiliz (dispose()'da durdurmuyoruz).
  void connectAndFind({
    required int size,
    required MediaStream localStream,
    String? authToken,
  }) {
    _socket?.disconnect();
    _socket?.dispose();
    _localStream = localStream;
    _iceServersFuture = _refreshIceServers();

    final optionBuilder =
        io.OptionBuilder().setTransports(['websocket']).disableAutoConnect();
    if (authToken != null) optionBuilder.setAuth({'token': authToken});
    _socket = io.io(signalingServerUrl, optionBuilder.build());

    _socket!.onConnect((_) {
      onStatusChange?.call('Grup aranıyor...');
      _socket!.emit('group-call-find', {'size': size});
    });
    _socket!.onConnectError((_) {
      onStatusChange?.call('Bağlantı hatası: sunucuya ulaşılamıyor.');
    });

    _socket!.on('group-call-matched', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        _roomId = map['roomId'] as String?;
        final participantsRaw = (map['participants'] as List?) ?? const [];
        final initiatorForIds =
            Set<String>.from((map['initiatorForIds'] as List?) ?? const []);

        _peers.clear();
        for (final raw in participantsRaw) {
          final p = Map<String, dynamic>.from(raw as Map);
          final id = p['socketId'] as String;
          _peers[id] = GroupCallPeer(
            socketId: id,
            displayName: p['displayName'] as String?,
            verified: p['verified'] as bool? ?? false,
            photoUrl: p['photoUrl'] as String?,
          );
        }
        onUpdate?.call();
        onStatusChange?.call('Grup bulundu, bağlanılıyor...');

        for (final id in _peers.keys) {
          unawaited(_startPeer(id, initiatorForIds.contains(id)));
        }
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-call-matched): $e');
      }
    });

    _socket!.on('signal', (data) async {
      try {
        final outer = Map<String, dynamic>.from(data as Map);
        final fromId = outer['fromId'] as String?;
        if (fromId == null || !_peers.containsKey(fromId)) return;
        final payload = Map<String, dynamic>.from(outer['data'] as Map);
        await _handleSignal(fromId, payload);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group signal): $e');
      }
    });

    _socket!.on('group-call-peer-left', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final socketId = map['socketId'] as String?;
        if (socketId == null) return;
        _closePeer(socketId);
        _peers.remove(socketId);
        onPeerLeft?.call(socketId);
        onUpdate?.call();
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-call-peer-left): $e');
      }
    });

    _socket!.on('group-call-ended', (_) {
      _cleanupAllPeers();
      onStatusChange?.call('Görüşme sona erdi.');
      onCallEnded?.call();
    });

    _socket!.on('account-restricted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onAccountRestricted
            ?.call(map['message'] as String? ?? 'Hesabın incelemeye alındı.');
      } catch (_) {}
    });

    _socket!.on('report-user-sent', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onReportSent?.call(map['id'] as String? ?? '');
      } catch (_) {}
    });

    _socket!.on('report-user-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onReportError?.call(map['message'] as String? ?? 'Şikayet gönderilemedi.');
      } catch (_) {}
    });

    _socket!.connect();
  }

  Future<RTCPeerConnection> _ensurePc(String socketId) {
    return _pcFutures.putIfAbsent(socketId, () => _createPc(socketId));
  }

  Future<RTCPeerConnection> _createPc(String socketId) async {
    if (_iceServersFuture != null) await _iceServersFuture;
    final pc = await createPeerConnection(_iceServers);
    if (_disposed) {
      pc.close();
      throw StateError('disposed');
    }
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _peers[socketId]?.remoteStream = event.streams[0];
        onUpdate?.call();
      }
    };
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _socket?.emit('signal', {
        'targetId': socketId,
        'data': {
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
    final peer = _peers[socketId];
    if (peer != null) peer.pc = pc;
    return pc;
  }

  Future<void> _startPeer(String socketId, bool isInitiator) async {
    try {
      final pc = await _ensurePc(socketId);
      if (_disposed || !_peers.containsKey(socketId)) return;
      if (isInitiator) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        if (_disposed || !_peers.containsKey(socketId)) return;
        _socket?.emit('signal', {
          'targetId': socketId,
          'data': {'type': 'offer', 'sdp': offer.sdp},
        });
      }
    } catch (_) {
      // pc kurulamadı (ör. ekran bu sırada kapandı) - sessizce vazgeç,
      // ilgili katılımcı zaten group-call-peer-left ile temizlenecek.
    }
  }

  Future<void> _handleSignal(String fromId, Map<String, dynamic> payload) async {
    final pc = await _ensurePc(fromId);
    if (_disposed) return;
    final type = payload['type'];

    if (type == 'offer') {
      // bkz. webrtc_service.dart _handleOffer() - AYNI kilit deseni, burada
      // katılımcı BAŞINA (per-peer) uygulanıyor ki bir katılımcının sinyali
      // diğerininkini bloklamasın.
      if (_handlingOffer[fromId] == true) return;
      _handlingOffer[fromId] = true;
      try {
        await pc.setRemoteDescription(
          RTCSessionDescription(payload['sdp'] as String, 'offer'),
        );
        if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveRemoteOffer &&
            pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer) {
          return;
        }
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _socket?.emit('signal', {
          'targetId': fromId,
          'data': {'type': 'answer', 'sdp': answer.sdp},
        });
      } finally {
        _handlingOffer[fromId] = false;
      }
    } else if (type == 'answer') {
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) return;
      if (_handlingAnswer[fromId] == true) return;
      _handlingAnswer[fromId] = true;
      try {
        await pc.setRemoteDescription(
          RTCSessionDescription(payload['sdp'] as String, 'answer'),
        );
      } finally {
        _handlingAnswer[fromId] = false;
      }
    } else if (type == 'candidate') {
      if (payload['candidate'] == null) return;
      await pc.addCandidate(
        RTCIceCandidate(
          payload['candidate'] as String,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        ),
      );
    }
  }

  void _closePeer(String socketId) {
    _peers[socketId]?.pc?.close();
    _pcFutures.remove(socketId);
    _handlingOffer.remove(socketId);
    _handlingAnswer.remove(socketId);
  }

  void _cleanupAllPeers() {
    for (final id in _peers.keys.toList()) {
      _closePeer(id);
    }
    _peers.clear();
    _roomId = null;
  }

  /// Bildir/şikayet et - grup görüşmesinde tek bir "partner" olmadığı için
  /// (1:1'deki reportUser'dan farklı) hedef AÇIKÇA belirtilmeli.
  void reportUser(String targetSocketId, String reason, {String? note}) {
    _socket?.emit('group-call-report-user', {
      'targetSocketId': targetSocketId,
      'reason': reason,
      'note': note,
    });
  }

  /// Odadan ayrılır ve YENİDEN kuyruğa girmez - ekran kapanırken kullanılır.
  void leaveRoom() {
    _socket?.emit('group-call-leave');
    _cleanupAllPeers();
  }

  /// Mevcut odadan ayrılıp YENİ bir grup arar - "Sıradaki grup" butonu için.
  /// Sunucu tarafı 'group-call-find' zaten önceki oda/kuyruk kaydını temizliyor
  /// (bkz. server.js), bu yüzden burada ayrıca 'group-call-leave' göndermeye
  /// gerek yok.
  void findNewGroup(int size) {
    _cleanupAllPeers();
    onUpdate?.call();
    onStatusChange?.call('Yeni grup aranıyor...');
    _socket?.emit('group-call-find', {'size': size});
  }

  void dispose() {
    _disposed = true;
    _cleanupAllPeers();
    _socket?.disconnect();
    _socket?.dispose();
    // ÖNEMLİ: _localStream burada durdurulmuyor - bu servisin sahibi değil
    // (bkz. sınıf üstü not), onu kimin başlattıysa (GroupCallScreen'in
    // sahip olduğu WebRTCService örneği) onun dispose()'u kapatır.
  }
}
