import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deep-link retry resets after network recovery', () {
    final source = File(
      'lib/screens/push_deep_link_transition_screen.dart',
    ).readAsStringSync();
    final monitor = File(
      'lib/services/network_availability_monitor.dart',
    ).readAsStringSync();

    expect(source, contains('_onNetworkAvailability'));
    expect(source, contains('_retryAttempts = 0'));
    expect(source, contains('_retryResetAfterRecovery = true'));
    expect(source, contains('İnternet bağlantısı geri geldi'));
    expect(source, contains('_networkSubscription?.cancel()'));
    expect(monitor, contains('ConnectivityNetworkAvailabilityMonitor'));
    expect(monitor, contains('ManualNetworkAvailabilityMonitor'));
  });
}
