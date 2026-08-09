import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/active_media_session_coordinator.dart';

void main() {
  final coordinator = ActiveMediaSessionCoordinator();

  tearDown(() async {
    await coordinator.closeAll();
  });

  test('closeAll closes every registered media session once', () async {
    final first = Object();
    final second = Object();
    var firstCalls = 0;
    var secondCalls = 0;

    coordinator.register(first, () => firstCalls++);
    coordinator.register(second, () async {
      secondCalls++;
    });

    await coordinator.closeAll();
    await coordinator.closeAll();

    expect(firstCalls, 1);
    expect(secondCalls, 1);
    expect(coordinator.activeSessionCount, 0);
  });

  test('screen dispose and central close cannot run cleanup twice', () async {
    final owner = Object();
    final release = Completer<void>();
    var calls = 0;

    coordinator.register(owner, () async {
      calls++;
      await release.future;
    });

    final centralClose = coordinator.closeAll();
    final screenClose = coordinator.close(owner);
    release.complete();
    await Future.wait([centralClose, screenClose]);

    expect(calls, 1);
  });

  test('one cleanup failure does not block the remaining sessions', () async {
    var completed = false;

    coordinator.register(Object(), () => throw StateError('boom'));
    coordinator.register(Object(), () => completed = true);

    await coordinator.closeAll();

    expect(completed, isTrue);
  });

  test('background suspend and resume are idempotent', () async {
    final owner = Object();
    var suspendCalls = 0;
    var resumeCalls = 0;

    coordinator.register(
      owner,
      () {},
      suspend: () => suspendCalls++,
      resume: () => resumeCalls++,
    );

    await coordinator.suspendAll();
    await coordinator.suspendAll();
    expect(suspendCalls, 1);
    expect(coordinator.isSuspended, isTrue);

    await coordinator.resumeAll();
    await coordinator.resumeAll();
    expect(resumeCalls, 1);
    expect(coordinator.isSuspended, isFalse);
  });
}
