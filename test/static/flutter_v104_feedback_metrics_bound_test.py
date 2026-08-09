from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "_maxTrackedActionKeys = 64" in a
assert "void _pruneTrackedKeys()" in a
assert "protectedKeys" in a
assert "_metrics.remove(key)" in a
print("flutter-v104-feedback-metrics-bound: başarılı")
