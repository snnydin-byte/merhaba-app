from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
service=(ROOT/"lib/services/session_feedback_network_recovery.dart").read_text()
main=(ROOT/"lib/main.dart").read_text()
assert "NetworkAvailabilityMonitor" in service
assert "final recovered = !_lastAvailable && available" in service
assert "key.startsWith('connection:')" in service
assert "SessionFeedbackLifecycle().initialize()" in main
print("flutter-v92-feedback-network-recovery: başarılı")
