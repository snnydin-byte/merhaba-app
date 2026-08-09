from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    'lib/screens/chat_screen.dart': [
        'sessionState.addListener(_handleSessionChanged)',
        'sessionState.removeListener(_handleSessionChanged)',
    ],
    'lib/screens/trusted_contacts_screen.dart': [
        'sessionState.addListener(_handleSessionChanged)',
        'sessionState.removeListener(_handleSessionChanged)',
    ],
    'lib/screens/discover_quiz_screen.dart': [
        'sessionState.addListener(_handleSessionChanged)',
        'sessionState.removeListener(_handleSessionChanged)',
    ],
    'lib/screens/leaderboard_screen.dart': ['AuthSessionBuilder('],
    'lib/screens/achievements_screen.dart': ['AuthSessionBuilder('],
}

for relative, required in TARGETS.items():
    text = (ROOT / relative).read_text(encoding='utf-8')
    assert 'AuthService().currentUser' not in text, relative
    assert 'AuthService.instance.currentUser' not in text, relative
    for token in required:
        assert token in text, f'{relative}: missing {token}'

print('flutter-v41-auth-session-scope: OK')
