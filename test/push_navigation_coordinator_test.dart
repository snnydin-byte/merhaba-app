import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/push_navigation_coordinator.dart';

void main() {
  setUp(() => PushNavigationCoordinator().resetForTesting());

  test('aynı hedef açıkken ikinci navigation reddedilir', () async {
    final release = Completer<void>();
    final first = PushNavigationCoordinator().runOnce('chat:user-1', () async {
      await release.future;
    });

    await Future<void>.delayed(Duration.zero);
    final second = await PushNavigationCoordinator().runOnce(
      'chat:user-1',
      () async {},
    );

    expect(second, isFalse);
    release.complete();
    expect(await first, isTrue);
  });

  test('hedef kapandıktan sonra yeniden açılabilir', () async {
    expect(
      await PushNavigationCoordinator().runOnce('group:g1', () async {}),
      isTrue,
    );
    expect(
      await PushNavigationCoordinator().runOnce('group:g1', () async {}),
      isTrue,
    );
  });
}
