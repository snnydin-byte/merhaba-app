import 'package:flutter/foundation.dart';

enum SocketConnectionPhase {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

enum AppConnectionChannel {
  messaging,
  call,
  groupCall,
  liveRoom,
}

enum ConnectionFailureKind {
  none,
  offline,
  serverUnavailable,
  sessionExpired,
  temporary,
}

@immutable
class SocketConnectionStatus {
  const SocketConnectionStatus({
    this.phase = SocketConnectionPhase.disconnected,
    this.message,
    this.updatedAt,
    this.failureKind = ConnectionFailureKind.none,
    this.retryable = true,
  });

  final SocketConnectionPhase phase;
  final String? message;
  final DateTime? updatedAt;
  final ConnectionFailureKind failureKind;
  final bool retryable;

  bool get isConnected => phase == SocketConnectionPhase.connected;
  bool get isBusy =>
      phase == SocketConnectionPhase.connecting ||
      phase == SocketConnectionPhase.reconnecting;

  SocketConnectionStatus copyWith({
    SocketConnectionPhase? phase,
    String? message,
    bool clearMessage = false,
    ConnectionFailureKind? failureKind,
    bool? retryable,
  }) {
    return SocketConnectionStatus(
      phase: phase ?? this.phase,
      message: clearMessage ? null : (message ?? this.message),
      updatedAt: DateTime.now(),
      failureKind: failureKind ?? this.failureKind,
      retryable: retryable ?? this.retryable,
    );
  }
}

@immutable
class AppConnectionState {
  const AppConnectionState({
    this.messaging = const SocketConnectionStatus(),
    this.call = const SocketConnectionStatus(),
    this.groupCall = const SocketConnectionStatus(),
    this.liveRoom = const SocketConnectionStatus(),
  });

  final SocketConnectionStatus messaging;
  final SocketConnectionStatus call;
  final SocketConnectionStatus groupCall;
  final SocketConnectionStatus liveRoom;

  bool get isFullyConnected => messaging.isConnected && call.isConnected;
  bool get hasError =>
      messaging.phase == SocketConnectionPhase.error ||
      call.phase == SocketConnectionPhase.error ||
      groupCall.phase == SocketConnectionPhase.error ||
      liveRoom.phase == SocketConnectionPhase.error;

  SocketConnectionStatus statusFor(AppConnectionChannel channel) {
    return switch (channel) {
      AppConnectionChannel.messaging => messaging,
      AppConnectionChannel.call => call,
      AppConnectionChannel.groupCall => groupCall,
      AppConnectionChannel.liveRoom => liveRoom,
    };
  }

  AppConnectionState copyWith({
    SocketConnectionStatus? messaging,
    SocketConnectionStatus? call,
    SocketConnectionStatus? groupCall,
    SocketConnectionStatus? liveRoom,
  }) {
    return AppConnectionState(
      messaging: messaging ?? this.messaging,
      call: call ?? this.call,
      groupCall: groupCall ?? this.groupCall,
      liveRoom: liveRoom ?? this.liveRoom,
    );
  }
}

class AppConnectionController {
  AppConnectionController._();

  static final AppConnectionController instance = AppConnectionController._();
  factory AppConnectionController() => instance;

  final ValueNotifier<AppConnectionState> state =
      ValueNotifier(const AppConnectionState());

  void updateMessaging(SocketConnectionPhase phase,
      {String? message,
      ConnectionFailureKind failureKind = ConnectionFailureKind.none,
      bool retryable = true}) {
    _update(AppConnectionChannel.messaging, phase,
        message: message, failureKind: failureKind, retryable: retryable);
  }

  void updateCall(SocketConnectionPhase phase,
      {String? message,
      ConnectionFailureKind failureKind = ConnectionFailureKind.none,
      bool retryable = true}) {
    _update(AppConnectionChannel.call, phase,
        message: message, failureKind: failureKind, retryable: retryable);
  }

  void updateGroupCall(SocketConnectionPhase phase,
      {String? message,
      ConnectionFailureKind failureKind = ConnectionFailureKind.none,
      bool retryable = true}) {
    _update(AppConnectionChannel.groupCall, phase,
        message: message, failureKind: failureKind, retryable: retryable);
  }

  void updateLiveRoom(SocketConnectionPhase phase,
      {String? message,
      ConnectionFailureKind failureKind = ConnectionFailureKind.none,
      bool retryable = true}) {
    _update(AppConnectionChannel.liveRoom, phase,
        message: message, failureKind: failureKind, retryable: retryable);
  }

  void _update(
    AppConnectionChannel channel,
    SocketConnectionPhase phase, {
    String? message,
    ConnectionFailureKind failureKind = ConnectionFailureKind.none,
    bool retryable = true,
  }) {
    final current = state.value.statusFor(channel).copyWith(
          phase: phase,
          message: message,
          clearMessage: message == null,
          failureKind: failureKind,
          retryable: retryable,
        );
    state.value = switch (channel) {
      AppConnectionChannel.messaging =>
        state.value.copyWith(messaging: current),
      AppConnectionChannel.call => state.value.copyWith(call: current),
      AppConnectionChannel.groupCall =>
        state.value.copyWith(groupCall: current),
      AppConnectionChannel.liveRoom => state.value.copyWith(liveRoom: current),
    };
  }

  void reset() {
    state.value = const AppConnectionState();
  }
}
