from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()

assert "class SessionFeedbackActionRunner" in actions
assert "final Map<String, Future<void>> _running" in actions
assert "final Map<String, DateTime> _cooldowns" in actions
assert "final existing = _running[key]" in actions
assert "if (existing != null) return existing" in actions
assert "if (!canRun(key, maxFailures: maxFailures))" in actions
assert "_running[key] = operation" in actions
assert "_running.remove(key)" in actions
assert "Duration(milliseconds: 750)" in actions
assert "key: 'session:login'" in actions
assert "key: 'connection:${channel.name}'" in actions
assert "key: 'connection:persistent'" in actions
assert "key: 'security:access-loss'" in actions
assert "FlutterError.reportError" in actions
assert "SessionFeedbackActionRunner().resetForTesting()" in helper

print("flutter-v87-feedback-action-lock: başarılı")
