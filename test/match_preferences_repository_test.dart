import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/match_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads defaults when no match preference is stored', () async {
    final value = await MatchPreferencesRepository().load();
    expect(value.genderFilter, 'herkes');
    expect(value.ageRangeEnabled, isFalse);
    expect(value.proximityEnabled, isFalse);
    expect(value.toServerMap(), isEmpty);
  });

  test('persists and exposes server match preferences', () async {
    final repository = MatchPreferencesRepository();
    await repository.setGenderFilter('kadın');
    await repository.setOnlyVerified(true);
    await repository.setAgeRange(enabled: true, min: 24, max: 42);
    await repository.setCountryFilter('TR');
    await repository.setProximity(enabled: true, maxDistanceKm: 75);
    await repository.setTextOnly(true);
    await repository.setSpeedRound(true);
    await repository.setRequireCommonInterest(true);

    final value = await repository.load();
    expect(value.maxDistanceKm, 75);
    expect(value.toServerMap(), {
      'genderFilter': 'kadın',
      'minAge': 24,
      'maxAge': 42,
      'onlyVerified': true,
      'countryFilter': 'TR',
      'textOnly': true,
      'speedRound': true,
      'requireCommonInterest': true,
    });
  });

  test('disabling optional filters removes their persisted keys', () async {
    final repository = MatchPreferencesRepository();
    await repository.setAgeRange(enabled: true, min: 18, max: 60);
    await repository.setProximity(enabled: true, maxDistanceKm: 100);
    await repository.setAgeRange(enabled: false, min: 18, max: 60);
    await repository.setProximity(enabled: false, maxDistanceKm: 100);

    final value = await repository.load();
    expect(value.ageRangeEnabled, isFalse);
    expect(value.proximityEnabled, isFalse);
  });
}
