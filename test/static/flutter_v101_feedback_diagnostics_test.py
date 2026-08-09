from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
actions=(ROOT/"lib/services/session_feedback_actions.dart").read_text()
screen=(ROOT/"lib/screens/feedback_diagnostics_screen.dart").read_text()
settings=(ROOT/"lib/screens/settings_screen.dart").read_text()
assert "class SessionFeedbackDiagnosticEntry" in actions
assert "diagnosticSnapshot" in actions
assert "List<SessionFeedbackDiagnosticEntry>.unmodifiable" in actions
assert "class FeedbackDiagnosticsScreen" in screen
assert "metrics.started" in screen
assert "metrics.timedOut" in screen
assert "if (kDebugMode)" in settings
assert "FeedbackDiagnosticsScreen" in settings
print("flutter-v101-feedback-diagnostics: başarılı")
