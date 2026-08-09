from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "key: 'security:access-loss'" in a
assert "key: 'security:$message'" not in a
print("flutter-v102-feedback-diagnostic-privacy: başarılı")
