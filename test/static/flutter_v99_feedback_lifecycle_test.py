from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
life=(ROOT/"lib/services/session_feedback_lifecycle.dart").read_text()
main=(ROOT/"lib/main.dart").read_text()
nav=(ROOT/"lib/services/session_navigation_coordinator.dart").read_text()
assert "class SessionFeedbackLifecycle" in life
assert "Future<void> initialize()" in life
assert "void clearForSessionEnd()" in life
assert "void clearForTesting()" in life
assert "SessionFeedbackLifecycle().initialize()" in main
assert "SessionFeedbackLifecycle().clearForSessionEnd()" in nav
print("flutter-v99-feedback-lifecycle: başarılı")
