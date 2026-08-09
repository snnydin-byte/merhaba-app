from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
helper = (ROOT / "lib/utils/session_transient_ui.dart").read_text()
assert "deduplicationKey" in helper
assert "_activeTransientUiKeys" in helper
assert "_claimTransientUiKey" in helper
assert helper.count("whenComplete(() => _releaseTransientUiKey(deduplicationKey))") == 2

missing = []
for path in (ROOT / "lib").rglob("*.dart"):
    if path.name == "session_transient_ui.dart":
        continue
    lines = path.read_text().splitlines()
    for i, line in enumerate(lines):
        if "showSessionDialog<" in line or "showSessionModalBottomSheet<" in line:
            window = "\n".join(lines[i:i+4])
            if "deduplicationKey:" not in window:
                missing.append(f"{path}:{i+1}")
assert not missing, missing
print("flutter-v80-transient-ui-dedup: başarılı")
