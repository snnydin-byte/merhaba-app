import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network recovery performs one controlled automatic deep-link retry',
      () {
    final source = File(
      'lib/screens/push_deep_link_transition_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_automaticRecoveryRetryUsed'));
    expect(source, contains('_runAutomaticRecoveryRetry'));
    expect(source, contains('automaticRecovery: true'));
    expect(source, contains("if (!available) {"));
    expect(source, contains('_automaticRecoveryRetryUsed = false'));
    expect(source, contains('_automaticRecoveryRetryUsed = true'));
    expect(
      source,
      contains('İçerik otomatik olarak yeniden doğrulanıyor.'),
    );
  });
}
