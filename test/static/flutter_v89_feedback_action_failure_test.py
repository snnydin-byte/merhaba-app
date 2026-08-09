from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()

assert "this.failureMessage" in actions
assert "onError: _showFailureFeedback" in actions
assert "void _showFailureFeedback" in actions
assert "action-failure:$key" in actions
assert "replaceCurrent: true" in actions
assert "priority: SessionFeedbackPriority.high" in actions
assert "SessionFeedbackSnackAction(action: this)" in actions
assert "onError?.call(error, stack)" in actions
assert "FlutterError.reportError" in actions
assert "Bağlantı yenilenemedi" in actions
assert "Giriş ekranı açılamadı" in actions
assert "Güvenli ekran açılamadı" in actions

print("flutter-v89-feedback-action-failure: başarılı")
