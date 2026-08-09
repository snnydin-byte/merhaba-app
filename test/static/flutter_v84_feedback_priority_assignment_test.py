from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
queue = (ROOT / "lib/services/session_feedback_queue.dart").read_text()

assert "inferSessionFeedbackPriority" in queue
assert "'oturumun süresi doldu'" in queue
assert "'yeniden giriş yap'" in queue
assert "'erişim'" in queue
assert "'engellendi'" in queue
assert "'başarıyla'" in queue
assert "inferSessionFeedbackPriority(snackBar.content, priority)" in queue
assert "inferSessionFeedbackPriority(banner.content, priority)" in queue

# Gerçek ekran çağrıları priority bilgisini açıkça taşımalı.
missing = []
for path in (ROOT / "lib").rglob("*.dart"):
    if path.name in {"session_transient_ui.dart", "session_feedback_queue.dart"}:
        continue
    text = path.read_text()
    cursor = 0
    while True:
        idx = text.find("showSessionSnackBar(", cursor)
        if idx < 0:
            break
        # İç içe action factory çağrıları ilk `);` noktasını erken bulabilir.
        # Priority çağrının devamında bulunduğundan güvenli bir pencere tara.
        block = text[idx:idx + 1400]
        if "priority:" not in block:
            missing.append(str(path))
        cursor = idx + 1
assert not missing, missing

print("flutter-v84-feedback-priority-assignment: başarılı")
