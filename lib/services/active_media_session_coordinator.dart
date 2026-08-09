import 'dart:async';

import 'package:flutter/foundation.dart';

typedef ActiveMediaCleanup = FutureOr<void> Function();
typedef ActiveMediaLifecycleAction = FutureOr<void> Function();

class _ActiveMediaSessionEntry {
  const _ActiveMediaSessionEntry({
    required this.cleanup,
    this.suspend,
    this.resume,
  });

  final ActiveMediaCleanup cleanup;
  final ActiveMediaLifecycleAction? suspend;
  final ActiveMediaLifecycleAction? resume;
}

/// Uygulama genelindeki aktif kamera, mikrofon, WebRTC ve LiveKit
/// oturumlarını tek noktadan yönetir.
///
/// - Güvenli çıkışta her kayıt en fazla bir kez kapatılır.
/// - Uygulama arka plana geçtiğinde kamera/mikrofon geçici olarak askıya
///   alınabilir.
/// - Ekran dispose'u ile merkezi çıkış eşzamanlı çalışsa bile aynı cleanup
///   ikinci kez başlatılmaz.
class ActiveMediaSessionCoordinator {
  ActiveMediaSessionCoordinator._();

  static final ActiveMediaSessionCoordinator instance =
      ActiveMediaSessionCoordinator._();
  factory ActiveMediaSessionCoordinator() => instance;

  final Map<Object, _ActiveMediaSessionEntry> _entries = {};
  final Set<Object> _closingOwners = {};
  Future<void>? _closingAll;
  Future<void>? _suspending;
  Future<void>? _resuming;
  bool _isSuspended = false;

  void register(
    Object owner,
    ActiveMediaCleanup cleanup, {
    ActiveMediaLifecycleAction? suspend,
    ActiveMediaLifecycleAction? resume,
  }) {
    _entries[owner] = _ActiveMediaSessionEntry(
      cleanup: cleanup,
      suspend: suspend,
      resume: resume,
    );
  }

  void unregister(Object owner) {
    _entries.remove(owner);
  }

  Future<void> close(Object owner) async {
    final entry = _entries.remove(owner);
    if (entry == null || !_closingOwners.add(owner)) return;
    try {
      await entry.cleanup();
    } catch (error, stack) {
      debugPrint('Aktif medya oturumu kapatılamadı: $error\n$stack');
    } finally {
      _closingOwners.remove(owner);
    }
  }

  Future<void> closeAll() {
    return _closingAll ??= _closeAll().whenComplete(() => _closingAll = null);
  }

  Future<void> _closeAll() async {
    final owners = List<Object>.from(_entries.keys);
    _isSuspended = false;
    for (final owner in owners) {
      await close(owner);
    }
  }

  Future<void> suspendAll() {
    return _suspending ??= _suspendAll().whenComplete(() => _suspending = null);
  }

  Future<void> _suspendAll() async {
    if (_isSuspended || _closingAll != null) return;
    _isSuspended = true;
    final entries = List<_ActiveMediaSessionEntry>.from(_entries.values);
    for (final entry in entries) {
      final action = entry.suspend;
      if (action == null) continue;
      try {
        await action();
      } catch (error, stack) {
        debugPrint('Aktif medya askıya alınamadı: $error\n$stack');
      }
    }
  }

  Future<void> resumeAll() {
    return _resuming ??= _resumeAll().whenComplete(() => _resuming = null);
  }

  Future<void> _resumeAll() async {
    if (!_isSuspended || _closingAll != null) return;
    _isSuspended = false;
    final entries = List<_ActiveMediaSessionEntry>.from(_entries.values);
    for (final entry in entries) {
      final action = entry.resume;
      if (action == null) continue;
      try {
        await action();
      } catch (error, stack) {
        debugPrint('Aktif medya devam ettirilemedi: $error\n$stack');
      }
    }
  }

  @visibleForTesting
  int get activeSessionCount => _entries.length;

  @visibleForTesting
  bool get isSuspended => _isSuspended;
}
