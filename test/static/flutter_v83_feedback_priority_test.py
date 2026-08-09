from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
queue = (ROOT / "lib/services/session_feedback_queue.dart").read_text()
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()
forced = (ROOT / "lib/utils/forced_navigation.dart").read_text()

assert "enum SessionFeedbackPriority { low, normal, high, critical }" in queue
assert "static const int _maxPending = 12" in queue
assert "request.priority == SessionFeedbackPriority.critical" in queue
assert "queued.priority.rank < SessionFeedbackPriority.high.rank" in queue
assert "messenger?.hideCurrentSnackBar()" in queue
assert "messenger?.hideCurrentMaterialBanner()" in queue
assert "SessionFeedbackPriority priority = SessionFeedbackPriority.normal" in helper
assert "priority: priority" in helper
assert "priority: SessionFeedbackPriority.high" in forced
print("flutter-v83-feedback-priority: başarılı")
