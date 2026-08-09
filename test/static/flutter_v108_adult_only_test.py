from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
login = (ROOT / "lib/screens/login_screen.dart").read_text()
policy = (ROOT / "lib/services/adult_age_policy.dart").read_text()
auth_repo = (ROOT / "lib/services/auth_repository.dart").read_text()
api = (ROOT / "lib/services/auth_api_client.dart").read_text()
profile = (ROOT / "lib/screens/profile_screen.dart").read_text()
webrtc = (ROOT / "lib/services/webrtc_service.dart").read_text()
call = (ROOT / "lib/services/call_service.dart").read_text()
settings = (ROOT / "lib/screens/settings_screen.dart").read_text()
privacy = (ROOT / "docs/privacy.html").read_text()
terms = (ROOT / "docs/terms.html").read_text()

assert "static const int minimumAge = 18" in policy
assert "AdultAgePolicy.latestEligibleBirthDate" in login
assert "adultConfirmed: _adultConfirmed" in login
assert "_buildGuestButton" not in login
assert "Misafir olarak devam et" not in login
assert "'birthDate': birthDate" in auth_repo
assert "'adultConfirmed': adultConfirmed" in auth_repo
assert "code: data['code'] as String?" in api
assert "AdultAgePolicy.toApiDate(birthDate)" in profile
assert "_ageController" not in profile
assert "headers: {'Authorization': 'Bearer $authToken'}" in webrtc
assert "headers: {'Authorization': 'Bearer $authToken'}" in call
assert "const String termsUrl" in settings
assert "Misafir kullanımına" in privacy
assert "yalnızca 18 yaşını doldurmuş" in terms

print("flutter-v108-adult-only: başarılı")
