from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()
banner = (ROOT / "lib/widgets/connection_status_banner.dart").read_text()

assert "class SessionFeedbackAction" in actions
assert "class SessionFeedbackActions" in actions
assert "label: 'Giriş yap'" in actions
assert "SessionExpirationCoordinator().handleExpiredSession" in actions
assert "ConnectionRetryController().retry(channel)" in actions
assert "retryPersistentConnections" in actions
assert "safeDestination" in actions
assert "SnackBarAction toSnackBarAction" in actions

assert "SnackBar sessionActionSnackBar" in helper
assert "SessionFeedbackSnackAction(action: action)" in helper

assert "ConnectionFailureKind.sessionExpired" in banner
assert "SessionFeedbackActions.forConnectionStatus" in banner
assert "SessionFeedbackActions.forPersistentConnections" in banner
assert "SessionFeedbackActionButton(" in banner
assert "enabled: sessionExpired || retryAvailable" in banner

print("flutter-v85-feedback-actions: başarılı")
