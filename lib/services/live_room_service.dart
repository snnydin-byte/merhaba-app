import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'webrtc_service.dart' show signalingServerUrl;

/// Canlı Yayın/Sesli Oda (Faz 1 - MVP). group_call_service.dart'taki MESH
/// mimarisinden KASITLI olarak farklı: burada tek bir RTCPeerConnection/peer
/// haritası YOK, medya tamamen LiveKit Cloud (SFU) üzerinden akıyor -
/// [_room] (livekit_client.Room) tek bağlantı noktası. Bu servis yalnızca
/// LiveKit'e bağlanmayı ve oda/rol/sohbet durumunu taşıyan Socket.IO
/// event'lerini (server.js'deki 'live-room-*' handler'ları) yönetir.
///
/// İzleyici rolünde asla kamera/mikrofon açılmaz (getUserMedia hiç
/// çağrılmaz) - bu yalnızca bir UI kısıtlaması değil, sunucu tarafında
/// generateJoinToken() ile token seviyesinde de zorlanıyor (bkz.
/// liveRoomMediaAdapter.js, canPublish: role === 'host' || 'co-host').
///
/// NOT: livekit_client ^2.8.1 API yüzeyi burada iyi niyetle, paketin bilinen
/// kararlı arayüzüne göre yazıldı ama gerçek bir LiveKit projesi/API key
/// olmadan uçtan uca test edilemedi (bkz. plan dosyası - Faz 0 kararı
/// bekleniyor). `flutter pub get` sonrası tip hatası çıkarsa önce
/// `livekit_client` sürümünün bu dosyadaki sınıf/metot adlarıyla
/// (Room, RoomOptions, createListener, TrackSubscribedEvent,
/// remoteParticipants) uyuştuğunu doğrula.
class LiveRoomChatMessage {
  final String fromUserId;
  final String? displayName;
  final String text;
  final DateTime sentAt;

  LiveRoomChatMessage({
    required this.fromUserId,
    this.displayName,
    required this.text,
    required this.sentAt,
  });
}

enum LiveRoomRole { host, coHost, viewer }

class LiveRoomService {
  io.Socket? _socket;
  livekit.Room? _room;
  livekit.EventsListener<livekit.RoomEvent>? _roomListener;
  String? _roomId;
  LiveRoomRole? _myRole;
  bool _disposed = false;

  String? get roomId => _roomId;
  LiveRoomRole? get myRole => _myRole;
  livekit.Room? get room => _room;

  /// Anlık (SFU'dan gelen) uzak katılımcılar - host/co-host video/ses
  /// track'leri. İzleyicinin kendi track'i asla burada yer almaz (hiç
  /// yayınlamıyor).
  Iterable<livekit.RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values ?? const [];

  void Function()? onUpdate;
  void Function(String status)? onStatusChange;
  void Function(String message)? onError;
  void Function()? onRoomEnded;
  void Function(int viewerCount)? onViewerCountChanged;
  void Function(LiveRoomChatMessage message)? onChatMessage;

  void _connectSocket(String authToken) {
    _socket?.disconnect();
    _socket?.dispose();
    final optionBuilder =
        io.OptionBuilder().setTransports(['websocket']).disableAutoConnect();
    optionBuilder.setAuth({'token': authToken});
    _socket = io.io(signalingServerUrl, optionBuilder.build());

    _socket!.onConnectError((_) {
      onStatusChange?.call('Bağlantı hatası: sunucuya ulaşılamıyor.');
    });
    _socket!.on('live-room-error', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onError?.call((map['message'] as String?) ?? 'Bilinmeyen bir hata oluştu.');
    });
    _socket!.on('live-room-ended', (_) {
      onRoomEnded?.call();
    });
    _socket!.on('live-room-viewer-count', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final count = map['viewerCount'] as int?;
      if (count != null) onViewerCountChanged?.call(count);
    });
    _socket!.on('live-room-chat-message', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final sentAtRaw = map['sentAt'] as String?;
      onChatMessage?.call(LiveRoomChatMessage(
        fromUserId: (map['fromUserId'] as String?) ?? '',
        displayName: map['displayName'] as String?,
        text: (map['text'] as String?) ?? '',
        sentAt: sentAtRaw != null ? DateTime.tryParse(sentAtRaw) ?? DateTime.now() : DateTime.now(),
      ));
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
      ..on<livekit.RoomDisconnectedEvent>((_) => onRoomEnded?.call());

    await _room!.connect(livekitUrl, token);
    if (_disposed) {
      // Ekran, LiveKit bağlantısı kurulurken kapandı (bkz. webrtc_service.dart
      // initLocalMedia()'daki aynı desen) - artık kimsenin sahiplenmeyeceği bu
      // odayı hemen kapatıp bırakıyoruz, kamera/mikrofon açık kalmasın.
      await _room?.disconnect();
      await _room?.dispose();
      _room = null;
    }
  }

  /// Yeni bir canlı oda açar (host rolü). [title] boş bırakılabilir.
  Future<void> createRoom({
    required String authToken,
    String? title,
  }) async {
    _connectSocket(authToken);
    _myRole = LiveRoomRole.host;
    onStatusChange?.call('Canlı oda oluşturuluyor...');

    _socket!.onConnect((_) {
      _socket!.emit('live-room-create', {'title': title ?? ''});
    });

    _socket!.on('live-room-created', (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final roomInfo = Map<String, dynamic>.from(map['room'] as Map);
      _roomId = roomInfo['id'] as String?;
      final token = map['token'] as String;
      final livekitUrl = map['livekitUrl'] as String;
      try {
        await _joinLiveKitRoom(livekitUrl, token);
        if (_disposed) return;
        // Host varsayılan olarak hem kamerasını hem mikrofonunu açar - viewer
        // için bu ASLA çağrılmaz (bkz. joinAsViewer).
        await _room!.localParticipant?.setCameraEnabled(true);
        await _room!.localParticipant?.setMicrophoneEnabled(true);
        onStatusChange?.call('Canlı yayındasın.');
        onUpdate?.call();
      } catch (err) {
        onError?.call('Canlı yayın başlatılamadı: $err');
      }
    });
  }

  /// Var olan bir odaya izleyici olarak katılır - kamera/mikrofon HİÇ
  /// açılmaz.
  Future<void> joinAsViewer({
    required String authToken,
    required String roomId,
  }) async {
    _connectSocket(authToken);
    _myRole = LiveRoomRole.viewer;
    _roomId = roomId;
    onStatusChange?.call('Canlı odaya katılınıyor...');

    _socket!.onConnect((_) {
      _socket!.emit('live-room-join', {'roomId': roomId});
    });

    _socket!.on('live-room-joined', (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final token = map['token'] as String;
      final livekitUrl = map['livekitUrl'] as String;
      try {
        await _joinLiveKitRoom(livekitUrl, token);
        if (_disposed) return;
        onStatusChange?.call('Canlı yayını izliyorsun.');
        onUpdate?.call();
      } catch (err) {
        onError?.call('Canlı odaya katılınamadı: $err');
      }
    });
  }

  void sendChatMessage(String text) {
    if (_roomId == null || text.trim().isEmpty) return;
    _socket?.emit('live-room-chat-send', {'roomId': _roomId, 'text': text.trim()});
  }

  void leaveRoom() {
    _socket?.emit('live-room-leave');
    _teardown();
  }

  void _teardown() {
    _roomListener?.dispose();
    _roomListener = null;
    _room?.disconnect();
    _room?.dispose();
    _room = null;
    _roomId = null;
    _myRole = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardown();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
