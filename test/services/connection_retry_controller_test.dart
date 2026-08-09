import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/app_connection_state.dart';
import 'package:merhaba_app/services/connection_retry_controller.dart';

void main() {
  final controller = ConnectionRetryController();
  final connections = AppConnectionController();

  setUp(() {
    controller.resetForTesting();
    connections.reset();
  });
  tearDown(() {
    controller.resetForTesting();
    connections.reset();
  });

  test('registered retry action runs once', () async {
    var calls = 0;
    controller.register(
      AppConnectionChannel.messaging,
      CallbackConnectionRetryAction(() => calls++),
    );

    await controller.retry(AppConnectionChannel.messaging);
    expect(calls, 1);
  });

  test('parallel retry calls are deduplicated', () async {
    var calls = 0;
    controller.register(
      AppConnectionChannel.call,
      CallbackConnectionRetryAction(() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }),
    );

    await Future.wait([
      controller.retry(AppConnectionChannel.call),
      controller.retry(AppConnectionChannel.call),
    ]);
    expect(calls, 1);
  });

  test('retry enters cooldown and blocks immediate retry', () async {
    var calls = 0;
    controller.register(
      AppConnectionChannel.messaging,
      CallbackConnectionRetryAction(() => calls++),
    );

    await controller.retry(AppConnectionChannel.messaging);
    await controller.retry(AppConnectionChannel.messaging);

    expect(calls, 1);
    expect(controller.remainingFor(AppConnectionChannel.messaging),
        greaterThan(Duration.zero));
    expect(controller.canRetry(AppConnectionChannel.messaging), isFalse);
  });

  test('connected state resets retry backoff', () async {
    controller.register(
      AppConnectionChannel.messaging,
      CallbackConnectionRetryAction(() {}),
    );

    await controller.retry(AppConnectionChannel.messaging);
    expect(controller.canRetry(AppConnectionChannel.messaging), isFalse);

    connections.updateMessaging(SocketConnectionPhase.connected);

    expect(
        controller.remainingFor(AppConnectionChannel.messaging), Duration.zero);
    expect(controller.canRetry(AppConnectionChannel.messaging), isTrue);
  });
}
