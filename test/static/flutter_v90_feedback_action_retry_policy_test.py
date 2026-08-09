from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()

assert "_failureBackoffSteps" in actions
assert "Duration(seconds: 2)" in actions
assert "Duration(seconds: 5)" in actions
assert "Duration(seconds: 15)" in actions
assert "final Map<String, int> _failureCounts" in actions
assert "int failureCount(String key)" in actions
assert "bool isExhausted" in actions
assert "int maxFailures = 3" in actions
assert "_failureCounts[key] = failures" in actions
assert "_failureCounts.remove(key)" in actions
assert "action-exhausted:$key" in actions
assert "Daha sonra dene" in actions
assert "if (!exhausted) SessionFeedbackSnackAction" in actions
assert "_failureCounts.clear()" in actions

print("flutter-v90-feedback-action-retry-policy: başarılı")
