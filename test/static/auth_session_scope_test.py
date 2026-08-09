from pathlib import Path

root = Path(__file__).resolve().parents[2]
main = (root / 'lib/main.dart').read_text()
widget = (root / 'lib/widgets/auth_session_builder.dart').read_text()
home = (root / 'lib/screens/home_screen.dart').read_text()
profile = (root / 'lib/screens/profile_screen.dart').read_text()
friends = (root / 'lib/screens/friends_screen.dart').read_text()
settings = (root / 'lib/screens/settings_screen.dart').read_text()

assert 'ValueListenableBuilder<AuthSessionState>' not in main
assert 'class AuthSessionBuilder' in widget
assert 'AuthSessionBuilder(' in home
assert 'AuthSessionBuilder(' in profile
assert 'AuthSessionBuilder(' in friends
assert 'sessionState.addListener(_syncPrivacyFromSession)' in settings
assert 'sessionState.removeListener(_syncPrivacyFromSession)' in settings
print('auth-session-scope: başarılı')
