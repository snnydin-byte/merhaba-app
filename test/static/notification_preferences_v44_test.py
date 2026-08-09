from pathlib import Path

root = Path(__file__).resolve().parents[2]
settings = (root / 'lib/screens/settings_screen.dart').read_text()
push = (root / 'lib/services/push_notification_service.dart').read_text()
repo = (root / 'lib/services/notification_preferences_repository.dart').read_text()

assert "SharedPreferences.getInstance()" not in settings
assert "PushNotificationService().setEnabled(value)" in settings
assert "_savingNotifications ? null : _setNotifications" in settings
assert "if (!_initialized || !_enabled) return;" in push
assert "if (!_initialized || !_enabled) return;" in push
assert "await unregisterCurrentToken();" in push
assert "await _localNotifications.cancelAll();" in push
assert "static const String key = 'notifications_enabled';" in repo
print('notification-preferences-v44: başarılı')
