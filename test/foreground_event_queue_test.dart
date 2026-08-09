import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/foreground_event_queue.dart';

void main() {
  final queue = ForegroundEventQueue();

  setUp(() => queue.resetForTesting(foreground: false));

  test('arka plandaki olay ön plana dönene kadar çalışmaz', () async {
    var calls = 0;
    queue.enqueue(PendingForegroundEvent(
      key: 'call:1',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      action: () => calls++,
    ));

    expect(calls, 0);
    queue.setForeground(true);
    await queue.drain();
    expect(calls, 1);
  });

  test('süresi dolmuş olay çalıştırılmaz', () async {
    var calls = 0;
    queue.enqueue(PendingForegroundEvent(
      key: 'expired',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      action: () => calls++,
    ));

    queue.setForeground(true);
    await queue.drain();
    expect(calls, 0);
  });

  test('aynı anahtarlı son olay eskisinin yerini alır', () async {
    final values = <int>[];
    queue.enqueue(PendingForegroundEvent(
      key: 'invite',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      action: () => values.add(1),
    ));
    queue.enqueue(PendingForegroundEvent(
      key: 'invite',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      action: () => values.add(2),
    ));

    queue.setForeground(true);
    await queue.drain();
    expect(values, [2]);
  });

  test('geçerliliğini kaybeden olay atlanır', () async {
    var valid = true;
    var calls = 0;
    queue.enqueue(PendingForegroundEvent(
      key: 'conditional',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      isStillValid: () => valid,
      action: () => calls++,
    ));
    valid = false;

    queue.setForeground(true);
    await queue.drain();
    expect(calls, 0);
  });
}
