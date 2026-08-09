import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/notification_preferences_repository.dart';

class MemoryNotificationStore implements NotificationPreferencesStore {
  bool? value;
  bool failWrites = false;

  @override
  Future<bool?> readEnabled() async => value;

  @override
  Future<void> writeEnabled(bool enabled) async {
    if (failWrites) throw StateError('write failed');
    value = enabled;
  }
}

void main() {
  test('bildirimler varsayılan olarak açıktır', () async {
    final repository = NotificationPreferencesRepository(
      store: MemoryNotificationStore(),
    );
    expect(await repository.loadEnabled(), isTrue);
  });

  test('bildirim tercihi kalıcı depoya yazılır', () async {
    final store = MemoryNotificationStore();
    final repository = NotificationPreferencesRepository(store: store);
    await repository.setEnabled(false);
    expect(await repository.loadEnabled(), isFalse);
  });

  test('depo yazma hatası çağırana aktarılır', () async {
    final store = MemoryNotificationStore()..failWrites = true;
    final repository = NotificationPreferencesRepository(store: store);
    expect(() => repository.setEnabled(false), throwsStateError);
  });
}
