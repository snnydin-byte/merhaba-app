from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
m=(ROOT/"lib/main.dart").read_text()
s=(ROOT/"lib/screens/settings_screen.dart").read_text()
assert "key: 'security:$message'" not in a
assert "_maxTrackedActionKeys = 64" in a
assert "Timer? _countdownTimer" in a
assert "if (crashlyticsReady)" in m
assert "if (kDebugMode)" in s
assert "print('YAKALANAN HATA" not in m
conflicts=[]
for p in (ROOT/"lib").rglob("*.dart"):
    text=p.read_text()
    if any(x in text for x in ("<<<<<<<", "=======", ">>>>>>>")):
        conflicts.append(str(p))
assert not conflicts, conflicts
print("flutter-v107-final-environment-audit: başarılı")
