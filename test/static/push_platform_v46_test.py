from pathlib import Path

root = Path(__file__).resolve().parents[2]
service = (root / 'lib/services/push_notification_service.dart').read_text()
platform = (root / 'lib/services/push_notification_platform.dart').read_text()

assert 'FirebaseMessaging.instance.getToken()' not in service
assert 'FirebaseMessaging.onMessage.listen' not in service
assert 'FlutterLocalNotificationsPlugin()' not in service
assert 'PushMessagingPlatform get _messagingPlatform' in service
assert 'LocalNotificationPlatform get _localNotifications' in service
assert 'abstract class PushMessagingPlatform' in platform
assert 'abstract class LocalNotificationPlatform' in platform
print('push-platform-v46: successful')
