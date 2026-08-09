from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
a=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
assert "Timer? _countdownTimer" in a
assert "Timer.periodic(const Duration(seconds: 1)" in a
assert "void _stopCountdownTimer()" in a
assert a.count("_stopCountdownTimer();") >= 2
print("flutter-v103-feedback-countdown-ticker: başarılı")
