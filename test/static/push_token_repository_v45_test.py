from pathlib import Path

root = Path(__file__).resolve().parents[2]
service = (root / 'lib/services/push_notification_service.dart').read_text()
repo = (root / 'lib/services/push_token_repository.dart').read_text()

assert "package:http/http.dart" not in service
assert "jsonEncode({'token': token" not in service
assert '_tokenRepository.register(' in service
assert '_tokenRepository.unregister(' in service
assert "http.Request(\n      'DELETE'" in repo
assert "'Authorization': 'Bearer $authToken'" in repo
print('push-token-repository-v45: başarılı')
