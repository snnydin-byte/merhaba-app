import 'dart:async';

/// Socket ve push kanallarından aynı olayın iki kez kullanıcıya gösterilmesini
/// engeller. Kayıtlar kısa ömürlüdür; süre dolunca aynı kimlik yeniden kabul
/// edilir (ör. daha sonraki yeni bir mesaj bildirimi).
class EventDeduplicationService {
  EventDeduplicationService._internal();
  static final EventDeduplicationService instance =
      EventDeduplicationService._internal();
  factory EventDeduplicationService() => instance;

  final Map<String, DateTime> _seenUntil = <String, DateTime>{};
  Timer? _cleanupTimer;

  bool claim(
    String key, {
    Duration ttl = const Duration(minutes: 5),
  }) {
    final normalized = key.trim();
    if (normalized.isEmpty) return false;
    final now = DateTime.now();
    final existing = _seenUntil[normalized];
    if (existing != null && existing.isAfter(now)) return false;
    _seenUntil[normalized] = now.add(ttl);
    _ensureCleanupTimer();
    return true;
  }

  void forget(String key) => _seenUntil.remove(key.trim());

  void _ensureCleanupTimer() {
    _cleanupTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      _seenUntil.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
      if (_seenUntil.isEmpty) {
        _cleanupTimer?.cancel();
        _cleanupTimer = null;
      }
    });
  }

  void resetForTesting() {
    _seenUntil.clear();
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }
}
