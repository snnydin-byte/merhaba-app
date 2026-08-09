from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "class SessionFeedbackActionStatus" in actions
assert "bool get canInvoke" in actions
assert "SessionFeedbackActionStatus statusFor" in actions
assert "final status = runner.statusFor" in actions
print("flutter-v95-feedback-action-status: başarılı")
