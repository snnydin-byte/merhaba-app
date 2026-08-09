import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected social screens do not read currentUser directly', () {
    const files = <String>[
      'lib/screens/friends_screen.dart',
      'lib/screens/group_info_screen.dart',
      'lib/screens/group_chat_screen.dart',
      'lib/screens/groups_screen.dart',
      'lib/screens/story_viewer_screen.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('AuthService().currentUser'),
        isFalse,
        reason: '$path doğrudan singleton currentUser okumamalı.',
      );
    }
  });

  test('session listeners are removed by stateful group/story screens', () {
    const files = <String>[
      'lib/screens/group_info_screen.dart',
      'lib/screens/group_chat_screen.dart',
      'lib/screens/groups_screen.dart',
      'lib/screens/story_viewer_screen.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('sessionState.addListener(_syncSessionUser)'));
      expect(source, contains('sessionState.removeListener(_syncSessionUser)'));
    }
  });
}
