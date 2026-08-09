import 'package:flutter/foundation.dart';

/// Oturum kapanışı ile Login route'unun kurulması arasındaki kısa fakat kritik
/// aralıkta eski async callback'lerin snackbar, dialog, bottom sheet veya yeni
/// bir navigation üretmesini engeller.
///
/// Kilit generation tabanlıdır. Eski bir çıkış akışının `unlock` çağrısı daha
/// yeni bir çıkışın kilidini yanlışlıkla açamaz.
class SessionUiLock {
  SessionUiLock._internal();
  static final SessionUiLock instance = SessionUiLock._internal();
  factory SessionUiLock() => instance;

  final ValueNotifier<bool> isLocked = ValueNotifier<bool>(false);
  int _generation = 0;

  int lock() {
    final generation = ++_generation;
    if (!isLocked.value) isLocked.value = true;
    return generation;
  }

  void unlock(int generation) {
    if (generation != _generation) return;
    if (isLocked.value) isLocked.value = false;
  }

  bool get allowsTransientUi => !isLocked.value;

  @visibleForTesting
  int get generation => _generation;

  @visibleForTesting
  void resetForTesting() {
    _generation++;
    isLocked.value = false;
  }
}
