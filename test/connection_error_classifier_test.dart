import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/app_connection_state.dart';
import 'package:merhaba_app/services/connection_error_classifier.dart';

void main() {
  test('classifies expired sessions as non-retryable', () {
    final result = classifyConnectionError('AUTH_EXPIRED');
    expect(result.kind, ConnectionFailureKind.sessionExpired);
    expect(result.retryable, isFalse);
  });
  test('classifies offline socket failures', () {
    final result =
        classifyConnectionError('SocketException: Failed host lookup');
    expect(result.kind, ConnectionFailureKind.offline);
    expect(result.retryable, isTrue);
  });
  test('classifies server failures', () {
    final result =
        classifyConnectionError('WebSocket error: connection refused');
    expect(result.kind, ConnectionFailureKind.serverUnavailable);
  });
}
