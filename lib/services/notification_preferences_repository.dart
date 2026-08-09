import 'package:shared_preferences/shared_preferences.dart';

abstract class NotificationPreferencesStore {
  Future<bool?> readEnabled();
  Future<void> writeEnabled(bool enabled);
}

class SharedPreferencesNotificationStore
    implements NotificationPreferencesStore {
  static const String key = 'notifications_enabled';

  @override
  Future<bool?> readEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setBool(key, enabled);
    if (!saved) {
      throw StateError('Bildirim tercihi kaydedilemedi.');
    }
  }
}

class NotificationPreferencesRepository {
  NotificationPreferencesRepository({NotificationPreferencesStore? store})
      : _store = store ?? SharedPreferencesNotificationStore();

  final NotificationPreferencesStore _store;

  Future<bool> loadEnabled() async => await _store.readEnabled() ?? true;

  Future<void> setEnabled(bool enabled) => _store.writeEnabled(enabled);
}
