from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
n=(ROOT/"lib/services/session_feedback_network_recovery.dart").read_text()
l=(ROOT/"lib/services/session_feedback_lifecycle.dart").read_text()
assert "try {" in n and "catch (_)" in n
assert "Duration(seconds: 3)" in n
assert "onError: (_)" in n
assert "Future<void>? _initialization" in l
assert "return _initialization ??= _initialize()" in l
print("flutter-v105-feedback-initialization-resilience: başarılı")
