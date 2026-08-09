from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "this.timeout = const Duration(seconds: 12)" in actions
assert "Duration timeout = const Duration(seconds: 12)" in actions
assert "Future<void>.sync(action).timeout(timeout)" in actions
print("flutter-v94-feedback-action-timeout: başarılı")
