from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()
queue = (ROOT / "lib/services/session_feedback_queue.dart").read_text()

assert "_cooldowns" in queue
assert "_claim" in queue
assert "Duration cooldown = const Duration(seconds: 2)" in helper
assert "Duration cooldown = const Duration(seconds: 3)" in helper
assert "showSessionMaterialBanner" in helper
assert "showGlobalSessionSnackBar" in helper
assert "showGlobalSessionMaterialBanner" in helper
assert "_snackBarKey" in helper
assert "_materialBannerKey" in helper
assert "_cooldowns.clear()" in queue

# Session-aware helper/merkezi kuyruk dışında doğrudan feedback gösterimi eklenmesin.
allowed = {"session_transient_ui.dart", "session_feedback_queue.dart"}
violations = []
for path in (ROOT / "lib").rglob("*.dart"):
    if path.name in allowed:
        continue
    text = path.read_text()
    if ".showSnackBar(" in text:
        violations.append(f"direct snack bar: {path}")
    if ".showMaterialBanner(" in text:
        violations.append(f"direct material banner: {path}")
assert not violations, violations

print("flutter-v81-transient-feedback-rate-limit: başarılı")
