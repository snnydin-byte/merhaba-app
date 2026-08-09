from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
text = (ROOT / 'lib/screens/settings_screen.dart').read_text(encoding='utf-8')

assert 'AuthService().currentUser' not in text
assert 'AuthService().isLoggedIn' not in text
assert 'optimisticUpdate' in text
assert 'rollback' in text
assert 'değişiklik geri alındı' in text
assert 'sessionState.addListener(_syncPrivacyFromSession)' in text
assert 'sessionState.removeListener(_syncPrivacyFromSession)' in text
assert 'if (_savingPrivacy || !_isLoggedIn) return;' in text
print('settings-privacy-v42: OK')
