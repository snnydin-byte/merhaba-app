import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection error classification remains wired', () {
    final state =
        File('lib/services/app_connection_state.dart').readAsStringSync();
    final classifier = File('lib/services/connection_error_classifier.dart')
        .readAsStringSync();
    final banner =
        File('lib/widgets/connection_status_banner.dart').readAsStringSync();
    expect(state, contains('ConnectionFailureKind'));
    expect(classifier, contains('sessionExpired'));
    expect(classifier, contains('offline'));
    expect(banner, contains('.retryable'));
  });
}
