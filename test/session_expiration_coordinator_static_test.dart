import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AUTH_EXPIRED bütün socket servislerinde merkezi çıkışı tetikler', () {
    const files = [
      'lib/services/messaging_service.dart',
      'lib/services/call_service.dart',
      'lib/services/group_call_service.dart',
      'lib/services/live_room_service.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('SessionExpirationCoordinator()'));
      expect(source, contains('ConnectionFailureKind.sessionExpired'));
    }
  });

  test('merkezi çıkış oturumu temizleyip navigator geçmişini sıfırlar', () {
    final source = File('lib/services/session_expiration_coordinator.dart')
        .readAsStringSync();
    expect(source, contains('AuthService().logout()'));
    expect(source, contains('SessionNavigationCoordinator().resetToLogin()'));
    expect(source, contains('AppConnectionController().reset()'));

    final navigation = File('lib/services/session_navigation_coordinator.dart')
        .readAsStringSync();
    expect(navigation, contains('pushAndRemoveUntil'));
    expect(navigation, contains('const LoginScreen()'));
  });
}
