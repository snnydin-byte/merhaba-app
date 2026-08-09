from pathlib import Path

root = Path(__file__).resolve().parents[1]
service = (root / 'lib/services/push_notification_service.dart').read_text()
deps = (root / 'lib/services/push_notification_dependencies.dart').read_text()
login = (root / 'lib/screens/login_screen.dart').read_text()
splash = (root / 'lib/screens/splash_screen.dart').read_text()
profile = (root / 'lib/screens/profile_screen.dart').read_text()

assert 'PushAuthSnapshot' in deps
assert 'addListener(VoidCallback listener)' in deps
assert '_handleAuthSessionChanged' in service
assert '_unregisterTokenForSession(deviceToken, previous)' in service
assert '_registerTokenForSession(deviceToken, next)' in service
assert '_lastRegisteredUserId' in service
assert 'registerTokenWithServer()' not in login
assert 'registerTokenWithServer()' not in splash
assert 'unregisterCurrentToken()' not in profile
print('flutter-v48-push-auth-lifecycle: başarılı')
