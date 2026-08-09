from pathlib import Path

root = Path(__file__).resolve().parents[1]
service = (root / 'lib/services/push_notification_service.dart').read_text()
deps = (root / 'lib/services/push_notification_dependencies.dart').read_text()

assert 'PushNotificationDependencies _dependencies' in service
assert '_serializeTokenSync' in service
assert '_tokenSyncTail' in service
assert 'AuthService().isLoggedIn' not in service
assert 'AuthService().token' not in service
assert 'class PushNotificationDependencies' in deps
assert 'abstract class PushAuthSession' in deps
print('flutter-v47-push-dependencies: başarılı')
