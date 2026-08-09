from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
queue = (ROOT / "lib/services/session_feedback_queue.dart").read_text()
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()
nav = (ROOT / "lib/services/session_navigation_coordinator.dart").read_text()

assert "class SessionFeedbackQueue" in queue
assert "scaffoldMessengerKey.currentState" in queue
assert "List<_SessionFeedbackRequest>" in queue
assert "_queuedOrActiveKeys" in queue
assert "if (!_queuedOrActiveKeys.add(key)) return false;" in queue
assert "await controller.closed;" in queue
assert "Banner kullanıcı aksiyonuna kadar açık kalabilir" in queue
assert "void clear()" in queue
assert "showGlobalSessionSnackBar" in helper
assert "showGlobalSessionMaterialBanner" in helper
assert "SessionFeedbackQueue().enqueueSnackBar" in helper
assert "SessionFeedbackQueue().enqueueMaterialBanner" in helper
assert "SessionFeedbackLifecycle().clearForSessionEnd();" in nav

print("flutter-v82-global-feedback-queue: başarılı")
