import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'active_media_session_coordinator.dart';
import 'app_connection_state.dart';
import 'connection_error_classifier.dart';
import 'socket_client_options.dart';
import 'foreground_event_queue.dart';
import 'event_deduplication_service.dart';
import 'session_expiration_coordinator.dart';
import 'connection_retry_controller.dart';
import 'auth_service.dart';
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

class LiveRoomViewer {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final bool verified;
  final bool isModerator;

  LiveRoomViewer({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.verified,
    required this.isModerator,
  });
}

class LiveRoomService {
  io.Socket? _socket;
  livekit.Room? _room;
  livekit.EventsListener<livekit.RoomEvent>? _roomListener;
  String? _roomId;
  String? _hostUserId;
  LiveRoomRole? _myRole;
  bool _disposed = false;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _backgroundSuspended = false;
  String? _authToken;
  String? _createTitle;
  bool _retryAsHost = false;
  late final ConnectionRetryAction _retryAction =
      CallbackConnectionRetryAction(_retryConnection);
  // Host'tan bağımsız, host'un sonradan atadığı bir yetki - bkz. server.js
  // 'live-room-moderator-changed'. myRole zaten host/co-host'u kapsıyor,
  // bu yalnızca "moderatör yapılmış bir izleyici" durumunu ekliyor.
  bool _isModerator = false;

  String? get roomId => _roomId;
  String? get hostUserId => _hostUserId;
  LiveRoomRole? get myRole => _myRole;
  bool get isModerator => _isModerator;
  // Kick/mute/moderatör-ata butonlarını göstermek için - host, co-host ya
  // da sonradan moderatör yapılmış biri.
  bool get canModerate =>
      _myRole == LiveRoomRole.host ||
      _myRole == LiveRoomRole.coHost ||
      _isModerator;
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
  // Moderasyon (Faz 2) - bkz. server.js'deki karşılık gelen event'ler.
  void Function(List<LiveRoomViewer> viewers)? onViewerList;
  void Function(String userId, bool isModerator)? onModeratorChanged;
  void Function(String userId, bool muted)? onMuteChanged;
  void Function()? onKicked;
  void Function(String fromUserId, String fromDisplayName)?
      onFriendRequestReceived;
  void Function(bool accepted, String? displayName)? onFriendRequestResult;
  void Function(String message)? onFriendRequestError;
  void Function(String id)? onReportSent;
  void Function(String message)? onReportError;

  void _connectSocket(String authToken) {
    AppConnectionController().updateLiveRoom(
      SocketConnectionPhase.connecting,
      message: 'Canlı oda bağlantısı kuruluyor…',
    );
    _socket?.disconnect();
    _socket?.dispose();
    _socket = io.io(
      signalingServerUrl,
      buildSocketClientOptions(authToken: authToken),
    );

    _socket!.onConnect((_) {
      AppConnectionController().updateLiveRoom(
        SocketConnectionPhase.connected,
      );
    });
    _socket!.onConnectError((error) {
      final failure = classifyConnectionError(error);
      if (failure.kind == ConnectionFailureKind.sessionExpired) {
        unawaited(SessionExpirationCoordinator().handleExpiredSession());
      }
      AppConnectionController().updateLiveRoom(
        SocketConnectionPhase.error,
        message: failure.message,
        failureKind: failure.kind,
        retryable: failure.retryable,
      );
      onStatusChange?.call(failure.message);
    });
    _socket!.onDisconnect((_) {
      if (_disposed) return;
      AppConnectionController().updateLiveRoom(
        SocketConnectionPhase.reconnecting,
        message: 'Canlı oda bağlantısı yenileniyor…',
      );
    });
    _socket!.on('live-room-error', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onError
          ?.call((map['message'] as String?) ?? 'Bilinmeyen bir hata oluştu.');
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
        sentAt: sentAtRaw != null
            ? DateTime.tryParse(sentAtRaw) ?? DateTime.now()
            : DateTime.now(),
      ));
    });
    _socket!.on('live-room-viewer-list', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final rawViewers = (map['viewers'] as List<dynamic>?) ?? [];
      final viewers = rawViewers.map((v) {
        final vm = Map<String, dynamic>.from(v as Map);
        return LiveRoomViewer(
          userId: vm['userId'] as String,
          displayName: (vm['displayName'] as String?) ?? 'Kullanıcı',
          photoUrl: vm['photoUrl'] as String?,
          verified: (vm['verified'] as bool?) ?? false,
          isModerator: (vm['isModerator'] as bool?) ?? false,
        );
      }).toList();
      onViewerList?.call(viewers);
    });
    _socket!.on('live-room-moderator-changed', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final userId = map['userId'] as String?;
      final isMod = (map['isModerator'] as bool?) ?? false;
      if (userId == null) return;
      // Kendi rolüm değiştiyse (host tarafından moderatör yapıldım/
      // moderatörlükten alındım) _isModerator'ü de güncelle - UI'daki
      // canModerate butonları buna göre anında değişsin.
      _updateSelfModeratorFlag(userId, isMod);
      onModeratorChanged?.call(userId, isMod);
    });
    _socket!.on('live-room-mute-changed', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final userId = map['userId'] as String?;
      final muted = (map['muted'] as bool?) ?? false;
      if (userId != null) onMuteChanged?.call(userId, muted);
    });
    _socket!.on('live-room-kicked', (_) {
      onKicked?.call();
      _teardown();
    });
    _socket!.on('live-room-friend-request-received', (data) {
      final fromUserIdForDedup =
          data is Map ? data['fromUserId']?.toString() : null;
      final roomIdForDedup = _roomId ?? 'unknown';
      if (fromUserIdForDedup != null &&
          !EventDeduplicationService().claim(
            'live-room-friend-request:$roomIdForDedup:$fromUserIdForDedup',
            ttl: const Duration(minutes: 5),
          )) {
        return;
      }
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final fromUserId = (map['fromUserId'] as String?) ?? '';
      final fromDisplayName =
          (map['fromDisplayName'] as String?) ?? 'Kullanıcı';
      if (fromUserId.isEmpty) return;
      void deliver() => onFriendRequestReceived?.call(
            fromUserId,
            fromDisplayName,
          );
      final queue = ForegroundEventQueue();
      if (!queue.isForeground.value) {
        final roomAtReceipt = _roomId;
        queue.enqueue(PendingForegroundEvent(
          key: 'live-room-friend-request:$fromUserId',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          isStillValid: () =>
              !_disposed && _roomId != null && _roomId == roomAtReceipt,
          action: deliver,
        ));
        return;
      }
      deliver();
    });
    _socket!.on('friend-request-result', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onFriendRequestResult?.call(
          (map['accepted'] as bool?) ?? false, map['displayName'] as String?);
    });
    _socket!.on('friend-request-error', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onFriendRequestError
          ?.call((map['message'] as String?) ?? 'Bilinmeyen bir hata oluştu.');
    });
    _socket!.on('report-user-sent', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onReportSent?.call((map['id'] as String?) ?? '');
    });
    _socket!.on('report-user-error', (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      onReportError
          ?.call((map['message'] as String?) ?? 'Bilinmeyen bir hata oluştu.');
    });

    _socket!.connect();
  }

  void _updateSelfModeratorFlag(String userId, bool isMod) {
    if (userId == AuthService().currentUser?.id) {
      _isModerator = isMod;
    }
  }

  Future<void> _joinLiveKitRoom(String livekitUrl, String token) async {
    _room = livekit.Room(
      roomOptions: const livekit.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      ),
    );
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

  Future<void> setMicrophoneEnabled(bool enabled) async {
    _micEnabled = enabled;
    if (!_backgroundSuspended && _myRole != LiveRoomRole.viewer) {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    _cameraEnabled = enabled;
    if (!_backgroundSuspended && _myRole != LiveRoomRole.viewer) {
      await _room?.localParticipant?.setCameraEnabled(enabled);
    }
  }

  Future<void> suspendMediaForBackground() async {
    if (_backgroundSuspended || _myRole == LiveRoomRole.viewer) return;
    _backgroundSuspended = true;
    await _room?.localParticipant?.setCameraEnabled(false);
    await _room?.localParticipant?.setMicrophoneEnabled(false);
  }

  Future<void> resumeMediaAfterBackground() async {
    if (!_backgroundSuspended || _disposed || _myRole == LiveRoomRole.viewer) {
      return;
    }
    _backgroundSuspended = false;
    await _room?.localParticipant?.setCameraEnabled(_cameraEnabled);
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
  }

  Future<void> createRoom({
    required String authToken,
    String? title,
  }) async {
    _disposed = false;
    ActiveMediaSessionCoordinator().register(
      this,
      closeForSessionExpiration,
      suspend: suspendMediaForBackground,
      resume: resumeMediaAfterBackground,
    );
    _authToken = authToken;
    _createTitle = title;
    _retryAsHost = true;
    ConnectionRetryController().register(
      AppConnectionChannel.liveRoom,
      _retryAction,
    );
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
      _hostUserId = roomInfo['hostUserId'] as String?;
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
    _disposed = false;
    ActiveMediaSessionCoordinator().register(
      this,
      closeForSessionExpiration,
      suspend: suspendMediaForBackground,
      resume: resumeMediaAfterBackground,
    );
    _authToken = authToken;
    _retryAsHost = false;
    ConnectionRetryController().register(
      AppConnectionChannel.liveRoom,
      _retryAction,
    );
    _connectSocket(authToken);
    _myRole = LiveRoomRole.viewer;
    _roomId = roomId;
    onStatusChange?.call('Canlı odaya katılınıyor...');

    _socket!.onConnect((_) {
      _socket!.emit('live-room-join', {'roomId': roomId});
    });

    _socket!.on('live-room-joined', (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final roomInfo = Map<String, dynamic>.from(map['room'] as Map);
      _hostUserId = roomInfo['hostUserId'] as String?;
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

  Future<void> _retryConnection() async {
    final token = _authToken;
    if (_disposed || token == null) return;
    final roomId = _roomId;
    if (_retryAsHost) {
      await createRoom(authToken: token, title: _createTitle);
    } else if (roomId != null) {
      await joinAsViewer(authToken: token, roomId: roomId);
    }
  }

  void sendChatMessage(String text) {
    if (_roomId == null || text.trim().isEmpty) return;
    _socket
        ?.emit('live-room-chat-send', {'roomId': _roomId, 'text': text.trim()});
  }

  /// İzleyici listesini ister - yalnızca host/co-host/moderatör için
  /// anlamlı, sunucu yetkisiz istekte 'live-room-error' döner (bkz.
  /// onError). Sonuç onViewerList üzerinden gelir.
  void requestViewerList() {
    if (_roomId == null) return;
    _socket?.emit('live-room-viewer-list', {'roomId': _roomId});
  }

  void addModerator(String targetUserId) {
    if (_roomId == null) return;
    _socket?.emit('live-room-add-moderator',
        {'roomId': _roomId, 'targetUserId': targetUserId});
  }

  void removeModerator(String targetUserId) {
    if (_roomId == null) return;
    _socket?.emit('live-room-remove-moderator',
        {'roomId': _roomId, 'targetUserId': targetUserId});
  }

  void kickUser(String targetUserId) {
    if (_roomId == null) return;
    _socket?.emit(
        'live-room-kick', {'roomId': _roomId, 'targetUserId': targetUserId});
  }

  void muteUser(String targetUserId) {
    if (_roomId == null) return;
    _socket?.emit(
        'live-room-mute', {'roomId': _roomId, 'targetUserId': targetUserId});
  }

  void unmuteUser(String targetUserId) {
    if (_roomId == null) return;
    _socket?.emit(
        'live-room-unmute', {'roomId': _roomId, 'targetUserId': targetUserId});
  }

  void reportUser(String targetUserId, {required String reason, String? note}) {
    if (_roomId == null) return;
    _socket?.emit('live-room-report-user', {
      'roomId': _roomId,
      'targetUserId': targetUserId,
      'reason': reason,
      'note': note ?? '',
    });
  }

  /// Yayın içinden arkadaşlık isteği gönderir - 1'e1 görüşmedeki
  /// 'friend-request'ten farklı bir sunucu event'i kullanır çünkü hedef
  /// tek bir "partner" değil, odadaki herhangi biri olabilir (bkz.
  /// server.js pendingLiveRoomFriendRequests yorumu).
  void sendFriendRequest(String targetUserId) {
    _socket?.emit('live-room-friend-request', {'targetUserId': targetUserId});
  }

  void respondToFriendRequest(bool accepted) {
    _socket?.emit('live-room-friend-request-response', {'accepted': accepted});
  }

  void leaveRoom() {
    AppConnectionController().updateLiveRoom(
      SocketConnectionPhase.disconnected,
    );
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

  Future<void> closeForSessionExpiration() async {
    if (_disposed) return;
    _disposed = true;
    ConnectionRetryController().unregister(
      AppConnectionChannel.liveRoom,
      _retryAction,
    );
    _socket?.emit('live-room-leave');
    _roomListener?.dispose();
    _roomListener = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
    _roomId = null;
    _hostUserId = null;
    _myRole = null;
    _isModerator = false;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    AppConnectionController().updateLiveRoom(
      SocketConnectionPhase.disconnected,
    );
    _backgroundSuspended = false;
    ActiveMediaSessionCoordinator().unregister(this);
  }

  void dispose() {
    ActiveMediaSessionCoordinator().unregister(this);
    if (_disposed) return;
    AppConnectionController().updateLiveRoom(
      SocketConnectionPhase.disconnected,
    );
    _disposed = true;
    ConnectionRetryController().unregister(
      AppConnectionChannel.liveRoom,
      _retryAction,
    );
    _teardown();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
