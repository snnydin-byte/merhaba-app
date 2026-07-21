import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'webrtc_service.dart' show signalingServerUrl;

/// Grup Eşleşme (3-8 kişi) - live_room_service.dart ile AYNI LiveKit (SFU)
/// mimarisi, tek fark: host/viewer ayrımı YOK, herkes eşit katılımcı (hepsi
/// yayınlar+izler). ESKİ mesh sürümünün (her katılımcı N-1 ayrı
/// RTCPeerConnection açardı, 8 kişide 28 bağlantı) YERİNE geçti - hem 8
/// kişiye ölçeklenebiliyor hem de sunucu tarafında "boşluk doldurma"
/// (groupMatchStore.js) artık mümkün, çünkü LiveKit'e sonradan katılmak
/// mesh'teki gibi TÜM mevcut katılımcılarla yeniden el sıkışma gerektirmiyor
/// - yalnızca aynı LiveKit odasına bağlanmak yeterli.
class GroupCallService {
  io.Socket? _socket;
  livekit.Room? _room;
  livekit.EventsListener<livekit.RoomEvent>? _roomListener;
  String? _roomId;
  int? _targetSize;
  bool _disposed = false;

  String? get roomId => _roomId;
  int? get targetSize => _targetSize;
  livekit.Room? get room => _room;
  Iterable<livekit.RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values ?? const [];

  void Function()? onUpdate;
  void Function(String status)? onStatusChange;
  void Function(String message)? onError;
  void Function()? onCallEnded;
  void Function(String message)? onAccountRestricted;
  void Function(String reportId)? onReportSent;
  void Function(String message)? onReportError;

  void connectAndFind({required int size, String? authToken}) {
    _socket?.disconnect();
    _socket?.dispose();
    _targetSize = size;

    final optionBuilder =
        io.OptionBuilder().setTransports(['websocket']).disableAutoConnect();
    if (authToken != null) optionBuilder.setAuth({'token': authToken});
    _socket = io.io(signalingServerUrl, optionBuilder.build());

    _socket!.onConnect((_) {
      onStatusChange?.call('Grup aranıyor...');
      _socket!.emit('group-match-find', {'size': size});
    });
    _socket!.onConnectError((_) {
      onStatusChange?.call('Bağlantı hatası: sunucuya ulaşılamıyor.');
    });
    _socket!.on('group-match-error', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onError?.call((map['message'] as String?) ?? 'Bilinmeyen bir hata oluştu.');
    });

    _socket!.on('group-match-joined', (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      _roomId = map['roomId'] as String?;
      _targetSize = map['targetSize'] as int? ?? _targetSize;
      final token = map['token'] as String;
      final livekitUrl = map['livekitUrl'] as String;
      onStatusChange?.call('Gruba bağlanılıyor...');
      try {
        await _joinLiveKitRoom(livekitUrl, token);
        if (_disposed) return;
        await _room!.localParticipant?.setCameraEnabled(true);
        await _room!.localParticipant?.setMicrophoneEnabled(true);
        onStatusChange?.call('Grupta yayındasın.');
        onUpdate?.call();
      } catch (err) {
        onError?.call('Gruba bağlanılamadı: $err');
      }
    });

    _socket!.on('account-restricted', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onAccountRestricted?.call((map['message'] as String?) ?? 'Hesabın incelemeye alındı.');
    });
    _socket!.on('report-user-sent', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onReportSent?.call((map['id'] as String?) ?? '');
    });
    _socket!.on('report-user-error', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onReportError?.call((map['message'] as String?) ?? 'Şikayet gönderilemedi.');
    });

    _socket!.connect();
  }

  Future<void> _joinLiveKitRoom(String livekitUrl, String token) async {
    _room = livekit.Room();
    _roomListener = _room!.createListener();
    _roomListener!
      ..on<livekit.TrackSubscribedEvent>((_) => onUpdate?.call())
      ..on<livekit.TrackUnsubscribedEvent>((_) => onUpdate?.call())
      ..on<livekit.ParticipantConnectedEvent>((_) => onUpdate?.call())
      ..on<livekit.ParticipantDisconnectedEvent>((_) => onUpdate?.call())
      ..on<livekit.RoomDisconnectedEvent>((_) => onCallEnded?.call());

    await _room!.connect(livekitUrl, token);
    if (_disposed) {
      // bkz. live_room_service.dart'taki AYNI desen - ekran, LiveKit
      // bağlantısı kurulurken kapandıysa kimsenin sahiplenmeyeceği odayı
      // hemen bırakıyoruz.
      await _room?.disconnect();
      await _room?.dispose();
      _room = null;
    }
  }

  /// Bildir/şikayet et - grup eşleşmesinde tek bir "partner" olmadığı için
  /// hedef userId AÇIKÇA belirtilmeli (LiveKit'te participant.identity ==
  /// userId, bkz. server.js generateJoinToken).
  void reportUser(String targetUserId, String reason, {String? note}) {
    _socket?.emit('group-match-report-user', {
      'targetUserId': targetUserId,
      'reason': reason,
      'note': note,
    });
  }

  /// Odadan ayrılır ve YENİDEN kuyruğa girmez - ekran kapanırken kullanılır.
  void leaveRoom() {
    _socket?.emit('group-match-leave');
    _teardown();
  }

  /// Mevcut odadan ayrılıp YENİ bir grup arar - "Sıradaki grup" butonu için.
  /// Sunucu tarafı 'group-match-find' zaten önceki oda/kuyruk kaydını
  /// temizliyor (bkz. server.js doLeaveGroupMatch), ayrıca 'group-match-
  /// leave' göndermeye gerek yok.
  void findNewGroup(int size) {
    _teardown();
    onUpdate?.call();
    onStatusChange?.call('Yeni grup aranıyor...');
    _targetSize = size;
    _socket?.emit('group-match-find', {'size': size});
  }

  void _teardown() {
    _roomListener?.dispose();
    _roomListener = null;
    _room?.disconnect();
    _room?.dispose();
    _room = null;
    _roomId = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardown();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
