import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('messaging and call signaling use one physical socket transport', () {
    final messaging =
        File('lib/services/messaging_service.dart').readAsStringSync();
    final call = File('lib/services/call_service.dart').readAsStringSync();
    final shared =
        File('lib/services/shared_socket_transport.dart').readAsStringSync();

    expect(messaging, contains('SharedSocketTransport().socketFor(authToken)'));
    expect(call, contains('SharedSocketTransport().socketFor(authToken)'));
    expect(messaging, isNot(contains('io.io(')));
    expect(call, isNot(contains('io.io(')));
    expect(shared, contains('io.Socket? _socket'));
    expect(shared, contains('return _socket = io.io('));
  });
}
