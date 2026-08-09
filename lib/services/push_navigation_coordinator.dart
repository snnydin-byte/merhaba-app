import 'dart:async';

import 'session_ui_lock.dart';

/// Push/deep-link kaynaklı aynı hedefin Navigator yığınına arka arkaya
/// eklenmesini engeller. Bir hedef açık olduğu veya açılma işlemi sürerken
/// aynı anahtar için yeni navigation isteği reddedilir.
class PushNavigationCoordinator {
  PushNavigationCoordinator._internal();
  static final PushNavigationCoordinator instance =
      PushNavigationCoordinator._internal();
  factory PushNavigationCoordinator() => instance;

  final Set<String> _activeTargets = <String>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  bool get hasActiveNavigation =>
      _activeTargets.isNotEmpty || _inFlight.isNotEmpty;

  bool isActive(String key) => _activeTargets.contains(key.trim());

  Future<bool> runOnce(
    String key,
    Future<void> Function() action,
  ) async {
    final normalized = key.trim();
    if (SessionUiLock().isLocked.value || normalized.isEmpty) return false;
    if (_activeTargets.contains(normalized) ||
        _inFlight.containsKey(normalized)) {
      return false;
    }

    final completer = Completer<void>();
    _inFlight[normalized] = completer.future;
    _activeTargets.add(normalized);
    try {
      await action();
      return true;
    } finally {
      _activeTargets.remove(normalized);
      _inFlight.remove(normalized);
      if (!completer.isCompleted) completer.complete();
    }
  }

  void resetForTesting() {
    _activeTargets.clear();
    _inFlight.clear();
  }
}
