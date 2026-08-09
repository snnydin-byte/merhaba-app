import 'dart:async';

import 'network_availability_monitor.dart';
import 'session_feedback_actions.dart';

/// İnternet geri geldiğinde tükenmiş bağlantı feedback aksiyonlarını sıfırlar.
class SessionFeedbackNetworkRecovery {
  SessionFeedbackNetworkRecovery._({
    NetworkAvailabilityMonitor? monitor,
  }) : _monitor = monitor ?? ConnectivityNetworkAvailabilityMonitor();

  static final SessionFeedbackNetworkRecovery instance =
      SessionFeedbackNetworkRecovery._();
  factory SessionFeedbackNetworkRecovery() => instance;

  final NetworkAvailabilityMonitor _monitor;
  StreamSubscription<bool>? _subscription;
  bool _lastAvailable = true;

  Future<void> ensureInitialized() async {
    if (_subscription != null) return;
    try {
      _lastAvailable = await _monitor.isAvailable().timeout(
            const Duration(seconds: 3),
          );
    } catch (_) {
      // Connectivity sorgusu platform başlatılırken başarısız olsa bile
      // uygulama açılışını engelleme; ilk stream olayı doğru durumu kurar.
      _lastAvailable = true;
    }
    _subscription = _monitor.availabilityChanges.listen(
      _handleAvailability,
      onError: (_) {
        // Geçici platform stream hatası feedback altyapısını kapatmaz.
      },
    );
  }

  void _handleAvailability(bool available) {
    final recovered = !_lastAvailable && available;
    _lastAvailable = available;
    if (!recovered) return;
    SessionFeedbackActionRunner().resetKeysWhere(
      (key) => key.startsWith('connection:'),
    );
  }

  Future<void> disposeForTesting() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastAvailable = true;
  }
}
