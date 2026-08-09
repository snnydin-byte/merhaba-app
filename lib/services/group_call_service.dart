import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'active_media_session_coordinator.dart';
import 'app_connection_state.dart';
import 'connection_error_classifier.dart';
import 'socket_client_options.dart';
import 'socket_event_payload.dart';
import 'foreground_event_queue.dart';
import 'event_deduplication_service.dart';
import 'session_expiration_coordinator.dart';
import 'connection_retry_controller.dart';
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
  static const _chatTopic = 'group-call-chat';

  io.Socket? _socket;
  livekit.Room? _room;
  livekit.EventsListener<livekit.RoomEvent>? _roomListener;
  String? _roomId;
  int? _targetSize;
  bool _disposed = false;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _backgroundSuspended = false;
  String? _authToken;
  late final ConnectionRetryAction _retryAction =
      CallbackConnectionRetryAction(_retryConnection);

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
  void Function(GroupCallChatMessage message)? onChatMessage;

  String get localParticipantName {
    final name = _room?.localParticipant?.name.trim() ?? '';
    return name.isEmpty ? 'Sen' : name;
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    _micEnabled = enabled;
    if (!_backgroundSuspended) {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    _cameraEnabled = enabled;
    if (!_backgroundSuspended) {
      await _room?.localParticipant?.setCameraEnabled(enabled);
    }
  }

  Future<void> suspendMediaForBackground() async {
    if (_backgroundSuspended) return;
    _backgroundSuspended = true;
    await _room?.localParticipant?.setCameraEnabled(false);
    await _room?.localParticipant?.setMicrophoneEnabled(false);
  }

  Future<void> resumeMediaAfterBackground() async {
    if (!_backgroundSuspended || _disposed) return;
    _backgroundSuspended = false;
    await _room?.localParticipant?.setCameraEnabled(_cameraEnabled);
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
  }

  void connectAndFind({required int size, String? authToken}) {
    _disposed = false;
    ActiveMediaSessionCoordinator().register(
      this,
      closeForSessionExpiration,
      suspend: suspendMediaForBackground,
      resume: resumeMediaAfterBackground,
    );
    _authToken = authToken;
    ConnectionRetryController().register(
      AppConnectionChannel.groupCall,
      _retryAction,
    );
    AppConnectionController().updateGroupCall(
      SocketConnectionPhase.connecting,
      message: 'Grup bağlantısı kuruluyor…',
    );
    _socket?.disconnect();
    _socket?.dispose();
    _targetSize = size;

    _socket = io.io(
      signalingServerUrl,
      buildSocketClientOptions(authToken: authToken),
    );

    _socket!.onConnect((_) {
      AppConnectionController().updateGroupCall(
        SocketConnectionPhase.connected,
      );
      onStatusChange?.call('Grup aranıyor...');
      _socket!.emit('group-match-find', {'size': size});
    });
    _socket!.onConnectError((error) {
      final failure = classifyConnectionError(error);
      if (failure.kind == ConnectionFailureKind.sessionExpired) {
        unawaited(SessionExpirationCoordinator().handleExpiredSession());
      }
      AppConnectionController().updateGroupCall(
        SocketConnectionPhase.error,
        message: failure.message,
        failureKind: failure.kind,
        retryable: failure.retryable,
      );
      onStatusChange?.call(failure.message);
    });
    _socket!.onDisconnect((_) {
      if (_disposed) return;
      AppConnectionController().updateGroupCall(
        SocketConnectionPhase.reconnecting,
        message: 'Grup bağlantısı yenileniyor…',
      );
    });
    _socket!.on('group-match-error', (data) {
      final map = socketEventMap(data);
      onError
          ?.call((map['message'] as String?) ?? 'Bilinmeyen bir hata oluştu.');
    });

    _socket!.on('group-match-joined', (data) {
      final roomIdForDedup = data is Map ? data['roomId']?.toString() : null;
      if (roomIdForDedup != null &&
          !EventDeduplicationService().claim(
            'group-match-joined:$roomIdForDedup',
            ttl: const Duration(minutes: 2),
          )) {
        return;
      }
      final map = socketEventMap(data);
      final roomId = map['roomId'] as String?;
      final targetSize = map['targetSize'] as int? ?? _targetSize;
      final token = map['token'] as String;
      final livekitUrl = map['livekitUrl'] as String;

      Future<void> joinWhenVisible() async {
        if (_disposed) return;
        _roomId = roomId;
        _targetSize = targetSize;
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
      }

      final queue = ForegroundEventQueue();
      if (!queue.isForeground.value) {
        queue.enqueue(PendingForegroundEvent(
          key: 'group-match-joined:${roomId ?? 'unknown'}',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          isStillValid: () => !_disposed && _socket?.connected == true,
          action: joinWhenVisible,
        ));
        return;
      }
      unawaited(joinWhenVisible());
    });

    _socket!.on('account-restricted', (data) {
      final map = socketEventMap(data);
      onAccountRestricted
          ?.call((map['message'] as String?) ?? 'Hesabın incelemeye alındı.');
    });
    _socket!.on('report-user-sent', (data) {
      final map = socketEventMap(data);
      onReportSent?.call((map['id'] as String?) ?? '');
    });
    _socket!.on('report-user-error', (data) {
      final map = socketEventMap(data);
      onReportError
          ?.call((map['message'] as String?) ?? 'Şikayet gönderilemedi.');
    });

    _socket!.connect();
  }

  void _retryConnection() {
    final size = _targetSize;
    if (_disposed || size == null) return;
    connectAndFind(size: size, authToken: _authToken);
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
      ..on<livekit.DataReceivedEvent>((event) {
        if (event.topic != _chatTopic) return;
        final text = utf8.decode(event.data, allowMalformed: true).trim();
        if (text.isEmpty) return;

        final participant = event.participant;
        final name = participant?.name.trim() ?? '';
        onChatMessage?.call(
          GroupCallChatMessage(
            text: text,
            senderName:
                name.isEmpty ? (participant?.identity ?? 'Katılımcı') : name,
            isMe: false,
          ),
        );
      })
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

  /// Bu odadaki tüm katılımcılara geçici ve güvenilir bir metin mesajı yollar.
  /// LiveKit veri kanalı kullanıldığı için ek sohbet sunucusu gerekmez.
  Future<bool> sendChatMessage(String text) async {
    final message = text.trim();
    final participant = _room?.localParticipant;
    if (message.isEmpty || participant == null) return false;

    try {
      await participant.publishData(
        utf8.encode(message),
        reliable: true,
        topic: _chatTopic,
      );
      return true;
    } catch (error) {
      // ignore: avoid_print
      print('Grup mesajÄ± gÃ¶nderilemedi: $error');
      return false;
    }
  }

  /// Odadan ayrılır ve YENİDEN kuyruğa girmez - ekran kapanırken kullanılır.
  void leaveRoom() {
    AppConnectionController().updateGroupCall(
      SocketConnectionPhase.disconnected,
    );
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

  Future<void> closeForSessionExpiration() async {
    if (_disposed) return;
    _disposed = true;
    ConnectionRetryController().unregister(
      AppConnectionChannel.groupCall,
      _retryAction,
    );
    _socket?.emit('group-match-leave');
    _roomListener?.dispose();
    _roomListener = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
    _roomId = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    onChatMessage = null;
    AppConnectionController().updateGroupCall(
      SocketConnectionPhase.disconnected,
    );
    _backgroundSuspended = false;
    ActiveMediaSessionCoordinator().unregister(this);
  }

  void dispose() {
    ActiveMediaSessionCoordinator().unregister(this);
    if (_disposed) return;
    AppConnectionController().updateGroupCall(
      SocketConnectionPhase.disconnected,
    );
    _disposed = true;
    ConnectionRetryController().unregister(
      AppConnectionChannel.groupCall,
      _retryAction,
    );
    _teardown();
    _socket?.disconnect();
    _socket?.dispose();
    onChatMessage = null;
  }
}

class GroupCallChatMessage {
  const GroupCallChatMessage({
    required this.text,
    required this.senderName,
    required this.isMe,
  });

  final String text;
  final String senderName;
  final bool isMe;
}
