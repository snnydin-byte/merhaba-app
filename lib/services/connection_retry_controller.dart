import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_connection_state.dart';

abstract class ConnectionRetryAction {
  FutureOr<void> retry();
}

class CallbackConnectionRetryAction implements ConnectionRetryAction {
  const CallbackConnectionRetryAction(this._callback);

  final FutureOr<void> Function() _callback;

  @override
  FutureOr<void> retry() => _callback();
}

@immutable
class ConnectionRetryStatus {
  const ConnectionRetryStatus({
    this.running = false,
    this.failureCount = 0,
    this.nextAllowedAt,
  });

  final bool running;
  final int failureCount;
  final DateTime? nextAllowedAt;

  Duration remainingAt(DateTime now) {
    final next = nextAllowedAt;
    if (next == null || !next.isAfter(now)) return Duration.zero;
    return next.difference(now);
  }

  bool canRetryAt(DateTime now) =>
      !running && remainingAt(now) == Duration.zero;

  ConnectionRetryStatus copyWith({
    bool? running,
    int? failureCount,
    DateTime? nextAllowedAt,
    bool clearNextAllowedAt = false,
  }) {
    return ConnectionRetryStatus(
      running: running ?? this.running,
      failureCount: failureCount ?? this.failureCount,
      nextAllowedAt:
          clearNextAllowedAt ? null : nextAllowedAt ?? this.nextAllowedAt,
    );
  }
}

class ConnectionRetryController {
  ConnectionRetryController._() {
    AppConnectionController().state.addListener(_handleConnectionStateChanged);
  }

  static final ConnectionRetryController instance =
      ConnectionRetryController._();
  factory ConnectionRetryController() => instance;

  static const List<Duration> _backoffSteps = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  final Map<AppConnectionChannel, ConnectionRetryAction> _actions = {};
  final Map<AppConnectionChannel, ConnectionRetryStatus> _statuses = {};
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  Timer? _countdownTimer;

  ValueListenable<int> get changes => _revision;

  void register(
    AppConnectionChannel channel,
    ConnectionRetryAction action,
  ) {
    _actions[channel] = action;
    _statuses.putIfAbsent(channel, () => const ConnectionRetryStatus());
    _notify();
  }

  void unregister(AppConnectionChannel channel, ConnectionRetryAction action) {
    if (identical(_actions[channel], action)) {
      _actions.remove(channel);
      _statuses.remove(channel);
      _notify();
    }
  }

  ConnectionRetryStatus statusFor(AppConnectionChannel channel) =>
      _statuses[channel] ?? const ConnectionRetryStatus();

  Duration remainingFor(
    AppConnectionChannel channel, {
    DateTime? now,
  }) =>
      statusFor(channel).remainingAt(now ?? DateTime.now());

  bool canRetry(AppConnectionChannel channel, {DateTime? now}) =>
      _actions.containsKey(channel) &&
      statusFor(channel).canRetryAt(now ?? DateTime.now());

  Future<void> retry(AppConnectionChannel channel) async {
    final action = _actions[channel];
    final now = DateTime.now();
    if (action == null || !canRetry(channel, now: now)) return;

    final previous = statusFor(channel);
    _statuses[channel] = previous.copyWith(running: true);
    _notify();

    try {
      await action.retry();
    } finally {
      final failureCount = previous.failureCount + 1;
      final stepIndex =
          (failureCount - 1).clamp(0, _backoffSteps.length - 1).toInt();
      _statuses[channel] = ConnectionRetryStatus(
        failureCount: failureCount,
        nextAllowedAt: DateTime.now().add(_backoffSteps[stepIndex]),
      );
      _ensureCountdownTimer();
      _notify();
    }
  }

  Future<void> retryPersistentConnections() async {
    await Future.wait([
      retry(AppConnectionChannel.messaging),
      retry(AppConnectionChannel.call),
    ]);
  }

  void resetBackoff(AppConnectionChannel channel) {
    if (!_statuses.containsKey(channel)) return;
    _statuses[channel] = const ConnectionRetryStatus();
    _stopCountdownIfIdle();
    _notify();
  }

  void _handleConnectionStateChanged() {
    final state = AppConnectionController().state.value;
    for (final channel in AppConnectionChannel.values) {
      if (state.statusFor(channel).phase == SocketConnectionPhase.connected) {
        final status = _statuses[channel];
        if (status != null &&
            (status.failureCount > 0 || status.nextAllowedAt != null)) {
          _statuses[channel] = const ConnectionRetryStatus();
        }
      }
    }
    _stopCountdownIfIdle();
    _notify();
  }

  void _ensureCountdownTimer() {
    if (_countdownTimer?.isActive ?? false) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _stopCountdownIfIdle();
      _notify();
    });
  }

  void _stopCountdownIfIdle() {
    final now = DateTime.now();
    final hasWaitingChannel = _statuses.values.any(
      (status) => status.remainingAt(now) > Duration.zero,
    );
    if (!hasWaitingChannel) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  void _notify() {
    _revision.value++;
  }

  @visibleForTesting
  void resetForTesting() {
    _actions.clear();
    _statuses.clear();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _notify();
  }
}
