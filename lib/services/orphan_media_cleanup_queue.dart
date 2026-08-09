import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'network_availability_monitor.dart';

typedef OrphanMediaDiscard = Future<bool> Function(
  String url, {
  bool enqueueOnFailure,
});

class PendingOrphanMediaCleanup {
  const PendingOrphanMediaCleanup({
    required this.url,
    required this.userId,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
  });

  final String url;
  final String userId;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;

  PendingOrphanMediaCleanup copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
  }) =>
      PendingOrphanMediaCleanup(
        url: url,
        userId: userId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'userId': userId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        if (nextAttemptAt != null)
          'nextAttemptAt': nextAttemptAt!.toUtc().toIso8601String(),
      };

  static PendingOrphanMediaCleanup? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final url = map['url'];
    final userId = map['userId'];
    final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
    if (url is! String ||
        url.trim().isEmpty ||
        userId is! String ||
        userId.trim().isEmpty ||
        createdAt == null) {
      return null;
    }
    return PendingOrphanMediaCleanup(
      url: url.trim(),
      userId: userId.trim(),
      createdAt: createdAt,
      attempts: map['attempts'] is int ? map['attempts'] as int : 0,
      nextAttemptAt: DateTime.tryParse(map['nextAttemptAt']?.toString() ?? ''),
    );
  }
}

abstract interface class OrphanMediaCleanupStore {
  Future<List<PendingOrphanMediaCleanup>> load();
  Future<void> save(List<PendingOrphanMediaCleanup> items);
}

class SharedPreferencesOrphanMediaCleanupStore
    implements OrphanMediaCleanupStore {
  static const _key = 'pending_orphan_media_cleanup_v1';

  @override
  Future<List<PendingOrphanMediaCleanup>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(PendingOrphanMediaCleanup.fromJson)
          .whereType<PendingOrphanMediaCleanup>()
          .toList();
    } catch (_) {
      await preferences.remove(_key);
      return const [];
    }
  }

  @override
  Future<void> save(List<PendingOrphanMediaCleanup> items) async {
    final preferences = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await preferences.remove(_key);
      return;
    }
    await preferences.setString(
      _key,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}

/// Ağ nedeniyle hemen temizlenemeyen geçici sohbet medyalarını kısa süreli
/// olarak diskte tutar. JWT hiçbir zaman kuyruğa yazılmaz; işlem yalnızca
/// yüklemeyi yapan hesap tekrar aktif olduğunda denenir.
class OrphanMediaCleanupQueue {
  OrphanMediaCleanupQueue._();
  static final OrphanMediaCleanupQueue _instance = OrphanMediaCleanupQueue._();
  factory OrphanMediaCleanupQueue() => _instance;

  static const _maxAge = Duration(minutes: 32);
  static const _maxItems = 50;

  OrphanMediaCleanupStore _store = SharedPreferencesOrphanMediaCleanupStore();
  NetworkAvailabilityMonitor _networkMonitor =
      ConnectivityNetworkAvailabilityMonitor();
  OrphanMediaDiscard? _discard;
  StreamSubscription<bool>? _networkSubscription;
  Timer? _retryTimer;
  bool _initialized = false;
  bool _flushing = false;
  Future<void>? _activeFlush;

  Future<void> initialize({required OrphanMediaDiscard discard}) async {
    _discard = discard;
    if (_initialized) {
      unawaited(flush());
      return;
    }
    _initialized = true;
    _networkSubscription = _networkMonitor.availabilityChanges.listen((online) {
      if (online) unawaited(flush());
    });
    AuthService().sessionState.addListener(_onSessionChanged);
    await flush();
  }

  void _onSessionChanged() => unawaited(flush());

  Future<void> enqueue(String url) async {
    final normalized = url.trim();
    final userId = AuthService().currentUser?.id;
    if (normalized.isEmpty || userId == null || userId.isEmpty) return;

    final now = DateTime.now().toUtc();
    final items = await _store.load();
    final retained = items
        .where((item) => now.difference(item.createdAt.toUtc()) < _maxAge)
        .toList();
    if (!retained
        .any((item) => item.url == normalized && item.userId == userId)) {
      retained.add(PendingOrphanMediaCleanup(
        url: normalized,
        userId: userId,
        createdAt: now,
      ));
    }
    if (retained.length > _maxItems) {
      retained.removeRange(0, retained.length - _maxItems);
    }
    await _store.save(retained);
    unawaited(flush());
  }

  Future<void> flush() {
    final active = _activeFlush;
    if (active != null) return active;
    final operation = _flushInternal();
    _activeFlush = operation;
    return operation.whenComplete(() {
      if (identical(_activeFlush, operation)) _activeFlush = null;
    });
  }

  /// Oturum tokenı temizlenmeden önce bu kullanıcıya ait bekleyen dosyalar
  /// için sınırlı bir son deneme yapar. Başarısız kayıtlar diskte kalır ve
  /// backend TTL temizliği son güvenlik ağı olmaya devam eder.
  Future<void> flushBeforeSessionEnd({
    required String userId,
    int maxItems = 3,
  }) async {
    final active = _activeFlush;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // Normal flush hatası çıkışı engellememeli.
      }
    }
    await _flushInternal(
      forcedUserId: userId,
      ignoreBackoff: true,
      maxItems: maxItems,
    );
  }

  /// Hesap sunucudan başarıyla silindiğinde aynı kullanıcıya ait yerel
  /// kuyruk kayıtlarını kaldırır. Sunucu tarafındaki kapsamlı hesap silme
  /// işlemi medya yaşam döngüsünün sorumluluğunu artık üstlenmiştir.
  Future<void> removeEntriesForUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return;
    final items = await _store.load();
    await _store.save(
      items.where((item) => item.userId != normalized).toList(),
    );
    _retryTimer?.cancel();
    _retryTimer = null;
    _scheduleNext(await _store.load(), DateTime.now().toUtc());
  }

  Future<void> _flushInternal({
    String? forcedUserId,
    bool ignoreBackoff = false,
    int? maxItems,
  }) async {
    if (_flushing || _discard == null) return;
    _flushing = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    try {
      final online = await _networkMonitor.isAvailable();
      final now = DateTime.now().toUtc();
      final activeUserId = forcedUserId ?? AuthService().currentUser?.id;
      final loaded = await _store.load();
      final pending = loaded
          .where((item) => now.difference(item.createdAt.toUtc()) < _maxAge)
          .toList();

      if (!online || activeUserId == null) {
        await _store.save(pending);
        _scheduleNext(pending, now);
        return;
      }

      final remaining = <PendingOrphanMediaCleanup>[];
      var attempted = 0;
      for (final item in pending) {
        if (item.userId != activeUserId) {
          remaining.add(item);
          continue;
        }
        if (maxItems != null && attempted >= maxItems) {
          remaining.add(item);
          continue;
        }
        final nextAttempt = item.nextAttemptAt?.toUtc();
        if (!ignoreBackoff && nextAttempt != null && nextAttempt.isAfter(now)) {
          remaining.add(item);
          continue;
        }
        attempted++;
        final removed = await _discard!(item.url, enqueueOnFailure: false);
        if (!removed) {
          final attempts = item.attempts + 1;
          remaining.add(item.copyWith(
            attempts: attempts,
            nextAttemptAt: now.add(_backoffFor(attempts)),
          ));
        }
      }
      await _store.save(remaining);
      _scheduleNext(remaining, now);
    } finally {
      _flushing = false;
    }
  }

  Duration _backoffFor(int attempts) {
    const seconds = [5, 15, 30, 60, 120];
    return Duration(
      seconds: seconds[(attempts - 1).clamp(0, seconds.length - 1).toInt()],
    );
  }

  void _scheduleNext(List<PendingOrphanMediaCleanup> items, DateTime now) {
    final userId = AuthService().currentUser?.id;
    final candidates = items
        .where((item) => item.userId == userId && item.nextAttemptAt != null)
        .map((item) => item.nextAttemptAt!.toUtc())
        .where((time) => time.isAfter(now))
        .toList();
    if (candidates.isEmpty) return;
    candidates.sort();
    _retryTimer = Timer(candidates.first.difference(now), () {
      unawaited(flush());
    });
  }

  Future<void> resetForTesting({
    OrphanMediaCleanupStore? store,
    NetworkAvailabilityMonitor? networkMonitor,
  }) async {
    _retryTimer?.cancel();
    await _networkSubscription?.cancel();
    AuthService().sessionState.removeListener(_onSessionChanged);
    _store = store ?? SharedPreferencesOrphanMediaCleanupStore();
    _networkMonitor = networkMonitor ?? ManualNetworkAvailabilityMonitor();
    _discard = null;
    _initialized = false;
    _flushing = false;
    _activeFlush = null;
  }
}

class MemoryOrphanMediaCleanupStore implements OrphanMediaCleanupStore {
  List<PendingOrphanMediaCleanup> items = [];

  @override
  Future<List<PendingOrphanMediaCleanup>> load() async => List.of(items);

  @override
  Future<void> save(List<PendingOrphanMediaCleanup> value) async {
    items = List.of(value);
  }
}
