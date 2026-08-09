import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/session_ui_lock.dart';

void main() {
  test('eski generation daha yeni oturum kilidini açamaz', () {
    final lock = SessionUiLock()..resetForTesting();
    final first = lock.lock();
    final second = lock.lock();

    lock.unlock(first);
    expect(lock.isLocked.value, isTrue);

    lock.unlock(second);
    expect(lock.isLocked.value, isFalse);
  });

  test('kilit geçici UI iznini kapatır', () {
    final lock = SessionUiLock()..resetForTesting();
    final generation = lock.lock();

    expect(lock.allowsTransientUi, isFalse);
    lock.unlock(generation);
    expect(lock.allowsTransientUi, isTrue);
  });
}
