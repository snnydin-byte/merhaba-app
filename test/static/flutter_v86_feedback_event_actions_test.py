from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()
banner = (ROOT / "lib/widgets/connection_status_banner.dart").read_text()
call_ui = (ROOT / "lib/services/call_ui_controller.dart").read_text()
forced = (ROOT / "lib/utils/forced_navigation.dart").read_text()

assert "forConnectionStatus" in actions
assert "forPersistentConnections" in actions
assert "connectionSnackBar" in actions
assert "securitySnackBar" in actions

assert "SessionFeedbackActions.forPersistentConnections(statuses)" in banner
assert "SessionFeedbackActions.forConnectionStatus" in banner

assert "_showSnack(message, retryable: true)" in call_ui
assert "SessionFeedbackActions.connectionSnackBar" in call_ui
assert "AppConnectionChannel.call" in call_ui

assert "SessionFeedbackActions.securitySnackBar" in forced
assert "navigatorKey.currentState" in forced
assert "Güvenli ekrana git" in actions

print("flutter-v86-feedback-event-actions: başarılı")
