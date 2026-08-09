from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "_failureMemoryTtl = Duration(minutes: 10)" in actions
assert "final Map<String, DateTime> _lastFailureAt" in actions
assert "void _expireStaleFailure" in actions
assert "_lastFailureAt[key] = DateTime.now()" in actions
assert "_lastFailureAt.clear()" in actions
print("flutter-v93-feedback-failure-aging: başarılı")
