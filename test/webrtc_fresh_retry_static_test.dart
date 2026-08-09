import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit random-match retry starts a fresh partner session', () {
    final source =
        File('lib/services/webrtc_service.dart').readAsStringSync();
    final methodStart = source.indexOf('void connectAndFindMatch(');
    final connectHandler = source.indexOf('_socket!.onConnect', methodStart);
    final setup = source.substring(methodStart, connectHandler);

    expect(setup, contains('_matchGeneration++;'));
    expect(setup, contains('_partnerId = null;'));
    expect(setup, contains('_cleanupPeerConnection();'));
  });
}
