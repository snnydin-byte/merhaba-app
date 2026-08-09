from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()
banner = (ROOT / "lib/widgets/connection_status_banner.dart").read_text()

assert "final ValueNotifier<int> _revision" in actions
assert "ValueListenable<int> get changes" in actions
assert "_notify();" in actions
assert "class SessionFeedbackActionButton" in actions
assert "class SessionFeedbackSnackAction" in actions
assert "CircularProgressIndicator(strokeWidth: 2)" in actions
assert "enabled && !running && !waiting && !exhausted" in actions
assert "onPressed: running || exhausted || waiting ? null : action.invoke" in actions
assert "SessionFeedbackActionButton(" in banner
assert "enabled: sessionExpired || retryAvailable" in banner
assert "SessionFeedbackSnackAction(action: action)" in helper
assert "SessionFeedbackActionButton" in helper

print("flutter-v88-feedback-action-progress: başarılı")
