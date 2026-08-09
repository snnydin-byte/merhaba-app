import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'app_connection_state.dart';
import 'connection_retry_controller.dart';
import 'session_expiration_coordinator.dart';
import 'session_feedback_queue.dart';

/// Kritik feedback yüzeylerinde kullanılan kullanıcı aksiyonlarını tek noktada
/// tanımlar. Böylece snackbar, banner ve bağlantı şeritleri aynı güvenli
/// davranışı çalıştırır.
class SessionFeedbackAction {
  const SessionFeedbackAction({
    required this.key,
    required this.label,
    required FutureOr<void> Function() onInvoke,
    this.cooldown = const Duration(milliseconds: 750),
    this.failureMessage = 'İşlem tamamlanamadı. Tekrar deneyebilirsin.',
    this.maxFailures = 3,
    this.timeout = const Duration(seconds: 12),
    this.maxFailureMessage =
        'Bu işlem art arda başarısız oldu. Bir süre sonra tekrar dene.',
  }) : _onInvoke = onInvoke;

  final String key;
  final String label;
  final Duration cooldown;
  final String failureMessage;
  final int maxFailures;
  final Duration timeout;
  final String maxFailureMessage;
  final FutureOr<void> Function() _onInvoke;

  bool get isRunning => SessionFeedbackActionRunner().isRunning(key);

  void invoke() {
    unawaited(
      SessionFeedbackActionRunner().run(
        key,
        _onInvoke,
        cooldown: cooldown,
        maxFailures: maxFailures,
        timeout: timeout,
        onError: _showFailureFeedback,
      ),
    );
  }

  void _showFailureFeedback(Object error, StackTrace stack) {
    final runner = SessionFeedbackActionRunner();
    final exhausted = runner.failureCount(key) >= maxFailures;
    SessionFeedbackQueue().enqueueSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: Text(exhausted ? maxFailureMessage : failureMessage),
            ),
            if (!exhausted) SessionFeedbackSnackAction(action: this),
          ],
        ),
        duration: const Duration(seconds: 7),
      ),
      key: exhausted ? 'action-exhausted:$key' : 'action-failure:$key',
      cooldown: const Duration(seconds: 2),
      replaceCurrent: true,
      priority: SessionFeedbackPriority.high,
    );
  }

  SnackBarAction toSnackBarAction({
    Color? textColor,
    Color? disabledTextColor,
  }) {
    return SnackBarAction(
      label: label,
      textColor: textColor,
      disabledTextColor: disabledTextColor,
      onPressed: invoke,
    );
  }
}

@immutable
class SessionFeedbackActionMetrics {
  const SessionFeedbackActionMetrics({
    this.started = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.blocked = 0,
    this.timedOut = 0,
  });

  final int started;
  final int succeeded;
  final int failed;
  final int blocked;
  final int timedOut;

  SessionFeedbackActionMetrics copyWith({
    int? started,
    int? succeeded,
    int? failed,
    int? blocked,
    int? timedOut,
  }) {
    return SessionFeedbackActionMetrics(
      started: started ?? this.started,
      succeeded: succeeded ?? this.succeeded,
      failed: failed ?? this.failed,
      blocked: blocked ?? this.blocked,
      timedOut: timedOut ?? this.timedOut,
    );
  }
}

@immutable
class SessionFeedbackDiagnosticEntry {
  const SessionFeedbackDiagnosticEntry({
    required this.key,
    required this.status,
    required this.metrics,
  });

  /// Tanılama ekranına yalnız sınırlı, uygulama tarafından tanımlı aksiyon
  /// anahtarları çıkar. Dinamik kullanıcı/sunucu metni bu alana girmez.
  final String key;
  final SessionFeedbackActionStatus status;
  final SessionFeedbackActionMetrics metrics;
}

@immutable
class SessionFeedbackActionStatus {
  const SessionFeedbackActionStatus({
    this.running = false,
    this.failureCount = 0,
    this.remaining = Duration.zero,
    this.exhausted = false,
  });

  final bool running;
  final int failureCount;
  final Duration remaining;
  final bool exhausted;

  bool get canInvoke => !running && !exhausted && remaining == Duration.zero;
}

/// Aynı mantıksal feedback aksiyonunun snackbar, banner ve bağlantı şeridi gibi
/// birden fazla yüzeyden eşzamanlı tetiklenmesini engeller.
class SessionFeedbackActionRunner {
  SessionFeedbackActionRunner._();

  static final SessionFeedbackActionRunner instance =
      SessionFeedbackActionRunner._();
  factory SessionFeedbackActionRunner() => instance;

  static const List<Duration> _failureBackoffSteps = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  final Map<String, Future<void>> _running = <String, Future<void>>{};
  final Map<String, DateTime> _cooldowns = <String, DateTime>{};
  static const Duration _failureMemoryTtl = Duration(minutes: 10);
  static const int _maxTrackedActionKeys = 64;

  final Map<String, int> _failureCounts = <String, int>{};
  final Map<String, DateTime> _lastFailureAt = <String, DateTime>{};
  final Map<String, SessionFeedbackActionMetrics> _metrics =
      <String, SessionFeedbackActionMetrics>{};
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  Timer? _countdownTimer;
  int _generation = 0;

  ValueListenable<int> get changes => _revision;

  bool isRunning(String key) => _running.containsKey(key);

  SessionFeedbackActionStatus statusFor(
    String key, {
    int maxFailures = 3,
    DateTime? now,
  }) {
    return SessionFeedbackActionStatus(
      running: isRunning(key),
      failureCount: failureCount(key),
      remaining: remainingFor(key, now: now),
      exhausted: isExhausted(key, maxFailures),
    );
  }

  int failureCount(String key) {
    _expireStaleFailure(key);
    return _failureCounts[key] ?? 0;
  }

  void _expireStaleFailure(String key, {DateTime? now}) {
    final failedAt = _lastFailureAt[key];
    if (failedAt == null) return;
    final current = now ?? DateTime.now();
    if (current.difference(failedAt) < _failureMemoryTtl) return;
    _failureCounts.remove(key);
    _lastFailureAt.remove(key);
    _cooldowns.remove(key);
  }

  bool isExhausted(String key, int maxFailures) =>
      failureCount(key) >= maxFailures;

  Duration remainingFor(String key, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final blockedUntil = _cooldowns[key];
    if (blockedUntil == null || !current.isBefore(blockedUntil)) {
      return Duration.zero;
    }
    return blockedUntil.difference(current);
  }

  bool canRun(String key, {DateTime? now, int? maxFailures}) {
    if (_running.containsKey(key)) return false;
    if (maxFailures != null && isExhausted(key, maxFailures)) return false;
    final current = now ?? DateTime.now();
    final blockedUntil = _cooldowns[key];
    return blockedUntil == null || !current.isBefore(blockedUntil);
  }

  SessionFeedbackActionMetrics metricsFor(String key) =>
      _metrics[key] ?? const SessionFeedbackActionMetrics();

  List<SessionFeedbackDiagnosticEntry> diagnosticSnapshot({
    DateTime? now,
  }) {
    final keys = <String>{
      ..._running.keys,
      ..._cooldowns.keys,
      ..._failureCounts.keys,
      ..._metrics.keys,
    }.toList(growable: false)
      ..sort();
    return List<SessionFeedbackDiagnosticEntry>.unmodifiable(
      keys.map(
        (key) => SessionFeedbackDiagnosticEntry(
          key: key,
          status: statusFor(key, now: now),
          metrics: metricsFor(key),
        ),
      ),
    );
  }

  void _updateMetrics(
    String key,
    SessionFeedbackActionMetrics Function(SessionFeedbackActionMetrics value)
        update,
  ) {
    _metrics[key] = update(metricsFor(key));
    _pruneTrackedKeys();
  }

  void _pruneTrackedKeys() {
    if (_metrics.length <= _maxTrackedActionKeys) return;
    final protectedKeys = <String>{..._running.keys, ..._failureCounts.keys};
    final removable = _metrics.keys
        .where((key) => !protectedKeys.contains(key))
        .toList(growable: false);
    final removeCount = _metrics.length - _maxTrackedActionKeys;
    for (final key in removable.take(removeCount)) {
      _metrics.remove(key);
      _cooldowns.remove(key);
      _lastFailureAt.remove(key);
    }
  }

  Future<void> run(
    String key,
    FutureOr<void> Function() action, {
    Duration cooldown = const Duration(milliseconds: 750),
    int maxFailures = 3,
    Duration timeout = const Duration(seconds: 12),
    void Function(Object error, StackTrace stack)? onError,
  }) {
    final existing = _running[key];
    if (existing != null) return existing;
    if (!canRun(key, maxFailures: maxFailures)) {
      _updateMetrics(
        key,
        (value) => value.copyWith(blocked: value.blocked + 1),
      );
      _notify();
      return Future<void>.value();
    }

    _updateMetrics(
      key,
      (value) => value.copyWith(started: value.started + 1),
    );
    final generation = _generation;
    late final Future<void> operation;
    operation = Future<void>(() async {
      var succeeded = false;
      try {
        await Future<void>.sync(action).timeout(timeout);
        succeeded = true;
        _updateMetrics(
          key,
          (value) => value.copyWith(succeeded: value.succeeded + 1),
        );
        _failureCounts.remove(key);
        _lastFailureAt.remove(key);
      } catch (error, stack) {
        _updateMetrics(
          key,
          (value) => value.copyWith(
            failed: value.failed + 1,
            timedOut: value.timedOut + (error is TimeoutException ? 1 : 0),
          ),
        );
        final failures = failureCount(key) + 1;
        _failureCounts[key] = failures;
        _lastFailureAt[key] = DateTime.now();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'session feedback actions',
            context: ErrorDescription('while running feedback action "$key"'),
          ),
        );
        if (generation == _generation) {
          onError?.call(error, stack);
        }
      } finally {
        if (generation == _generation) {
          _running.remove(key);
          final failures = failureCount(key);
          final wait = succeeded
              ? cooldown
              : _failureBackoffSteps[(failures - 1)
                  .clamp(0, _failureBackoffSteps.length - 1)
                  .toInt()];
          _cooldowns[key] = DateTime.now().add(wait);
          _pruneCooldowns();
          _ensureCountdownTimer();
          _notify();
        }
      }
    });

    _running[key] = operation;
    _notify();
    return operation;
  }

  void _ensureCountdownTimer() {
    if (_countdownTimer?.isActive ?? false) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _cooldowns.removeWhere(
        (key, blockedUntil) =>
            !now.isBefore(blockedUntil) && !_failureCounts.containsKey(key),
      );
      if (_cooldowns.values
          .every((blockedUntil) => !now.isBefore(blockedUntil))) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
      _notify();
    });
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _pruneCooldowns() {
    if (_cooldowns.length <= 64) return;
    final now = DateTime.now();
    _cooldowns.removeWhere(
      (_, blockedUntil) => !now.isBefore(blockedUntil),
    );
  }

  void resetKey(String key) {
    _running.remove(key);
    _cooldowns.remove(key);
    _failureCounts.remove(key);
    _lastFailureAt.remove(key);
    _notify();
  }

  void resetKeysWhere(bool Function(String key) predicate) {
    final keys = <String>{
      ..._running.keys,
      ..._cooldowns.keys,
      ..._failureCounts.keys,
    }.where(predicate).toList(growable: false);
    for (final key in keys) {
      _running.remove(key);
      _cooldowns.remove(key);
      _failureCounts.remove(key);
      _lastFailureAt.remove(key);
    }
    if (keys.isNotEmpty) _notify();
  }

  void _notify() {
    _revision.value++;
  }

  void cancelAll() {
    _stopCountdownTimer();
    _generation++;
    _running.clear();
    _cooldowns.clear();
    _failureCounts.clear();
    _lastFailureAt.clear();
    _metrics.clear();
    _notify();
  }

  @visibleForTesting
  int get runningCount => _running.length;

  @visibleForTesting
  void resetForTesting() {
    _stopCountdownTimer();
    _generation++;
    _running.clear();
    _cooldowns.clear();
    _failureCounts.clear();
    _lastFailureAt.clear();
    _metrics.clear();
    _notify();
  }
}

class SessionFeedbackActionButton extends StatelessWidget {
  const SessionFeedbackActionButton({
    super.key,
    required this.action,
    this.compact = false,
    this.enabled = true,
    this.textColor,
  });

  final SessionFeedbackAction action;
  final bool compact;
  final bool enabled;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final runner = SessionFeedbackActionRunner();
    return ValueListenableBuilder<int>(
      valueListenable: runner.changes,
      builder: (context, _, __) {
        final status = runner.statusFor(
          action.key,
          maxFailures: action.maxFailures,
        );
        final running = status.running;
        final exhausted = status.exhausted;
        final remaining = status.remaining;
        final waiting = remaining > Duration.zero;
        return Semantics(
          button: true,
          enabled: enabled && status.canInvoke,
          liveRegion: running,
          label: running
              ? '${action.label} işlemi sürüyor'
              : exhausted
                  ? '${action.label} daha sonra denenebilir'
                  : waiting
                      ? '${action.label} için bekleniyor'
                      : action.label,
          child: TextButton(
            onPressed: enabled && !running && !waiting && !exhausted
                ? action.invoke
                : null,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 9,
                vertical: compact ? 4 : 5,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: textColor,
            ),
            child: running
                ? SizedBox(
                    width: compact ? 14 : 16,
                    height: compact ? 14 : 16,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    exhausted
                        ? 'Daha sonra dene'
                        : waiting
                            ? '${remaining.inSeconds + 1} sn'
                            : action.label,
                    style: TextStyle(fontSize: compact ? 10 : 11),
                  ),
          ),
        );
      },
    );
  }
}

class SessionFeedbackSnackAction extends StatelessWidget {
  const SessionFeedbackSnackAction({
    super.key,
    required this.action,
  });

  final SessionFeedbackAction action;

  @override
  Widget build(BuildContext context) {
    final runner = SessionFeedbackActionRunner();
    return ValueListenableBuilder<int>(
      valueListenable: runner.changes,
      builder: (context, _, __) {
        final status = runner.statusFor(
          action.key,
          maxFailures: action.maxFailures,
        );
        final running = status.running;
        final exhausted = status.exhausted;
        final waiting = status.remaining > Duration.zero;
        return Semantics(
          button: true,
          enabled: status.canInvoke,
          liveRegion: running,
          label: running
              ? '${action.label} işlemi sürüyor'
              : exhausted
                  ? '${action.label} daha sonra denenebilir'
                  : action.label,
          child: TextButton(
            onPressed: running || exhausted || waiting ? null : action.invoke,
            child: running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(exhausted ? 'Daha sonra dene' : action.label),
          ),
        );
      },
    );
  }
}

class SessionFeedbackActions {
  SessionFeedbackActions._();

  /// Geçersiz/süresi dolmuş oturumu güvenli biçimde kapatıp Login'e gider.
  static SessionFeedbackAction login() {
    return SessionFeedbackAction(
      key: 'session:login',
      label: 'Giriş yap',
      failureMessage: 'Giriş ekranı açılamadı. Tekrar deneyebilirsin.',
      onInvoke: SessionExpirationCoordinator().handleExpiredSession,
    );
  }

  /// Belirli bir socket kanalını mevcut backoff/race korumalarıyla yeniler.
  static SessionFeedbackAction retryConnection(AppConnectionChannel channel) {
    return SessionFeedbackAction(
      key: 'connection:${channel.name}',
      label: 'Tekrar dene',
      failureMessage: 'Bağlantı yenilenemedi. Tekrar deneyebilirsin.',
      onInvoke: () => ConnectionRetryController().retry(channel),
    );
  }

  /// Kalıcı mesajlaşma ve arama bağlantılarını birlikte yeniler.
  static SessionFeedbackAction retryPersistentConnections() {
    return SessionFeedbackAction(
      key: 'connection:persistent',
      label: 'Tekrar dene',
      failureMessage: 'Bağlantılar yenilenemedi. Tekrar deneyebilirsin.',
      onInvoke: ConnectionRetryController().retryPersistentConnections,
    );
  }

  /// Bağlantı durumuna göre bütün yüzeylerde aynı aksiyonu üretir.
  static SessionFeedbackAction? forConnectionStatus(
    SocketConnectionStatus status,
    AppConnectionChannel channel,
  ) {
    if (status.failureKind == ConnectionFailureKind.sessionExpired) {
      return login();
    }
    if (status.phase == SocketConnectionPhase.error && status.retryable) {
      return retryConnection(channel);
    }
    return null;
  }

  /// Kalıcı mesajlaşma + arama durumlarının ortak yüzeyi için aksiyon üretir.
  static SessionFeedbackAction? forPersistentConnections(
    Iterable<SocketConnectionStatus> statuses,
  ) {
    final values = statuses.toList(growable: false);
    if (values.any(
      (status) => status.failureKind == ConnectionFailureKind.sessionExpired,
    )) {
      return login();
    }
    if (values.any(
      (status) =>
          status.phase == SocketConnectionPhase.error && status.retryable,
    )) {
      return retryPersistentConnections();
    }
    return null;
  }

  /// Erişim/güvenlik uyarısından güvenli bir hedefe yönlendiren özel eylem.
  static SessionFeedbackAction safeDestination({
    String key = 'security:safe-destination',
    String label = 'Güvenli ekrana git',
    String failureMessage = 'Güvenli ekran açılamadı. Tekrar deneyebilirsin.',
    required FutureOr<void> Function() onInvoke,
  }) {
    return SessionFeedbackAction(
      key: key,
      label: label,
      failureMessage: failureMessage,
      onInvoke: onInvoke,
    );
  }

  static SnackBar connectionSnackBar({
    required String message,
    required AppConnectionChannel channel,
    Duration duration = const Duration(seconds: 6),
  }) {
    final action = retryConnection(channel);
    return SnackBar(
      content: Row(
        children: [
          Expanded(child: Text(message)),
          SessionFeedbackSnackAction(action: action),
        ],
      ),
      duration: duration,
    );
  }

  static SnackBar securitySnackBar({
    required String message,
    required FutureOr<void> Function() onSafeDestination,
    Duration duration = const Duration(seconds: 7),
  }) {
    final action = safeDestination(
      key: 'security:access-loss',
      onInvoke: onSafeDestination,
    );
    return SnackBar(
      content: Row(
        children: [
          Expanded(child: Text(message)),
          SessionFeedbackSnackAction(action: action),
        ],
      ),
      duration: duration,
    );
  }
}
