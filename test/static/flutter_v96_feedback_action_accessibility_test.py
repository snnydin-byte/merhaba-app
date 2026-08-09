from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert actions.count("Semantics(") >= 2
assert "liveRegion: running" in actions
assert "işlemi sürüyor" in actions
assert "daha sonra denenebilir" in actions
assert "enabled: status.canInvoke" in actions
print("flutter-v96-feedback-action-accessibility: başarılı")
