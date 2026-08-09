from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
actions = (ROOT / "lib/services/session_feedback_actions.dart").read_text()
queue = (ROOT / "lib/services/session_feedback_queue.dart").read_text()
lifecycle = (ROOT / "lib/services/session_feedback_lifecycle.dart").read_text()
recovery = (ROOT / "lib/services/session_feedback_action_recovery.dart").read_text()
network = (ROOT / "lib/services/session_feedback_network_recovery.dart").read_text()

required = [
    "SessionFeedbackActionRunner",
    "SessionFeedbackActionStatus",
    "SessionFeedbackActionMetrics",
    "_failureBackoffSteps",
    "_failureMemoryTtl",
    "Future<void>.sync(action).timeout(timeout)",
    "void cancelAll()",
    "void resetKey(String key)",
]
for item in required:
    assert item in actions, item

assert "static const int _maxPending = 12" in queue
assert "SessionFeedbackLifecycle" in lifecycle
assert "resetKey('connection:${channel.name}')" in recovery
assert "key.startsWith('connection:')" in network

conflicts = []
for path in (ROOT / "lib").rglob("*.dart"):
    text = path.read_text()
    if any(marker in text for marker in ("<<<<<<<", "=======", ">>>>>>>")):
        conflicts.append(str(path))
assert not conflicts, conflicts

print("flutter-v100-feedback-final-audit: başarılı")
