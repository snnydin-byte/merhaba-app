from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "class SessionFeedbackActionMetrics" in actions
assert "this.started = 0" in actions
assert "this.timedOut = 0" in actions
assert "SessionFeedbackActionMetrics metricsFor" in actions
assert "error is TimeoutException" in actions
assert "blocked: value.blocked + 1" in actions
assert "_metrics.clear()" in actions
print("flutter-v98-feedback-action-metrics: başarılı")
