from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
m=(ROOT/"lib/main.dart").read_text()
assert "void main() {\n  var crashlyticsReady = false;" in m
assert "if (crashlyticsReady)" in m
assert "if (kDebugMode)" in m
assert "unawaited(PushNotificationService().init())" in m
assert "YAKALANAN HATA" not in m
print("flutter-v106-release-error-reporting: başarılı")
