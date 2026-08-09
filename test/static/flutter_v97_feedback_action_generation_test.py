from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
nav=(ROOT/"lib/services/session_navigation_coordinator.dart").read_text()
assert "int _generation = 0" in actions
assert "final generation = _generation" in actions
assert "if (generation != _generation) return" in actions
assert "void cancelAll()" in actions
assert "SessionFeedbackLifecycle().clearForSessionEnd()" in nav
print("flutter-v97-feedback-action-generation: başarılı")
