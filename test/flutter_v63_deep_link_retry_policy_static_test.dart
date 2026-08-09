import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deep-link retry is bounded and cooled down', () {
    final source = File(
      'lib/screens/push_deep_link_transition_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_maxRetryAttempts = 3'));
    expect(source, contains('_retryCooldownSeconds'));
    expect(source, contains('Timer.periodic'));
    expect(source, contains('0 => 2'));
    expect(source, contains('1 => 4'));
    expect(source, contains('_ => 8'));
    expect(source, contains('_retryLimitReached'));
    expect(source, contains('Maksimum deneme sayısına ulaşıldı'));
    expect(source, contains('_retryCooldownTimer?.cancel()'));
  });
}
