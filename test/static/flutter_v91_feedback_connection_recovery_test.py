from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
recovery=(ROOT/"lib/services/session_feedback_action_recovery.dart").read_text()
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
main=(ROOT/"lib/main.dart").read_text()
assert "AppConnectionController().state.addListener" in recovery
assert "resetKey('connection:${channel.name}')" in recovery
assert "resetKey('connection:persistent')" in recovery
assert "void resetKey(String key)" in actions
assert "SessionFeedbackLifecycle().initialize()" in main
print("flutter-v91-feedback-connection-recovery: başarılı")
