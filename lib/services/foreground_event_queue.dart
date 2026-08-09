import 'dart:async';

import 'package:flutter/foundation.dart';

import 'session_ui_lock.dart';

typedef ForegroundEventAction = FutureOr<void> Function();
typedef ForegroundEventValidator = bool Function();

class PendingForegroundEvent {
  const PendingForegroundEvent({
    required this.key,
    required this.expiresAt,
    required this.action,
    this.isStillValid,
  });

  final String key;
  final DateTime expiresAt;
  final ForegroundEventAction action;
  final ForegroundEventValidator? isStillValid;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);
  bool get canRun => !isExpired && (isStillValid?.call() ?? true);
}

/// Uygulama arka plandayken gelen, kullanıcı arayüzü gerektiren kısa ömürlü
/// socket olaylarını tutar. Aynı [key] ile gelen yeni olay eskisini değiştirir.
/// Uygulama ön plana döndüğünde yalnızca süresi dolmamış ve hâlâ geçerli olan
/// olaylar çalıştırılır.
class ForegroundEventQueue {
  ForegroundEventQueue._internal();
  static final ForegroundEventQueue instance = ForegroundEventQueue._internal();
  factory ForegroundEventQueue() => instance;

  final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);
  final Map<String, PendingForegroundEvent> _pending = {};
  Future<void>? _draining;

  int get pendingCount => _pending.length;

  void setForeground(bool value) {
    if (isForeground.value == value) return;
    isForeground.value = value;
    if (value) unawaited(drain());
  }

  bool enqueue(PendingForegroundEvent event) {
    if (SessionUiLock().isLocked.value || event.isExpired) return false;
    _pending[event.key] = event;
    if (isForeground.value) unawaited(drain());
    return true;
  }

  void cancel(String key) => _pending.remove(key);

  void clear() => _pending.clear();

  Future<void> drain() {
    final inProgress = _draining;
    if (inProgress != null) return inProgress;
    final future = _drainInternal();
    _draining = future;
    return future.whenComplete(() => _draining = null);
  }

  Future<void> _drainInternal() async {
    if (!isForeground.value || SessionUiLock().isLocked.value) {
      if (SessionUiLock().isLocked.value) _pending.clear();
      return;
    }
    final events = _pending.values.toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    for (final event in events) {
      if (!isForeground.value || SessionUiLock().isLocked.value) {
        if (SessionUiLock().isLocked.value) _pending.clear();
        return;
      }
      _pending.remove(event.key);
      if (!event.canRun) continue;
      await event.action();
    }
  }

  @visibleForTesting
  void resetForTesting({bool foreground = true}) {
    _pending.clear();
    isForeground.value = foreground;
    _draining = null;
  }
}
