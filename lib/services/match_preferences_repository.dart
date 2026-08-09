import 'package:shared_preferences/shared_preferences.dart';

const String matchGenderFilterPrefKey = 'match_gender_filter';
const String matchMinAgePrefKey = 'match_min_age';
const String matchMaxAgePrefKey = 'match_max_age';
const String matchOnlyVerifiedPrefKey = 'match_only_verified';
const String matchCountryFilterPrefKey = 'match_country_filter';
const String matchMaxDistanceKmPrefKey = 'match_max_distance_km';
const String matchTextOnlyPrefKey = 'match_text_only';
const String matchSpeedRoundPrefKey = 'match_speed_round';
const String matchRequireCommonInterestPrefKey =
    'match_require_common_interest';

class MatchPreferences {
  final String genderFilter;
  final int? minAge;
  final int? maxAge;
  final bool onlyVerified;
  final String countryFilter;
  final int? maxDistanceKm;
  final bool textOnly;
  final bool speedRound;
  final bool requireCommonInterest;

  const MatchPreferences({
    this.genderFilter = 'herkes',
    this.minAge,
    this.maxAge,
    this.onlyVerified = false,
    this.countryFilter = '',
    this.maxDistanceKm,
    this.textOnly = false,
    this.speedRound = false,
    this.requireCommonInterest = false,
  });

  bool get ageRangeEnabled => minAge != null || maxAge != null;
  bool get proximityEnabled => maxDistanceKm != null;

  Map<String, dynamic> toServerMap() {
    final result = <String, dynamic>{};
    if (genderFilter != 'herkes') result['genderFilter'] = genderFilter;
    if (minAge != null) result['minAge'] = minAge;
    if (maxAge != null) result['maxAge'] = maxAge;
    if (onlyVerified) result['onlyVerified'] = true;
    if (countryFilter.isNotEmpty) result['countryFilter'] = countryFilter;
    if (textOnly) result['textOnly'] = true;
    if (speedRound) result['speedRound'] = true;
    if (requireCommonInterest) result['requireCommonInterest'] = true;
    return result;
  }
}

class MatchPreferencesRepository {
  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<MatchPreferences> load() async {
    final prefs = await _prefs();
    return MatchPreferences(
      genderFilter: prefs.getString(matchGenderFilterPrefKey) ?? 'herkes',
      minAge: prefs.getInt(matchMinAgePrefKey),
      maxAge: prefs.getInt(matchMaxAgePrefKey),
      onlyVerified: prefs.getBool(matchOnlyVerifiedPrefKey) ?? false,
      countryFilter: prefs.getString(matchCountryFilterPrefKey) ?? '',
      maxDistanceKm: prefs.getInt(matchMaxDistanceKmPrefKey),
      textOnly: prefs.getBool(matchTextOnlyPrefKey) ?? false,
      speedRound: prefs.getBool(matchSpeedRoundPrefKey) ?? false,
      requireCommonInterest:
          prefs.getBool(matchRequireCommonInterestPrefKey) ?? false,
    );
  }

  Future<void> setGenderFilter(String value) async {
    if (!const {'herkes', 'erkek', 'kadın'}.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Geçersiz cinsiyet filtresi');
    }
    await _requireSaved(
        (await _prefs()).setString(matchGenderFilterPrefKey, value));
  }

  Future<void> setOnlyVerified(bool value) async {
    await _requireSaved(
        (await _prefs()).setBool(matchOnlyVerifiedPrefKey, value));
  }

  Future<void> setAgeRange(
      {required bool enabled, required int min, required int max}) async {
    if (min < 18 || max > 120 || min > max) {
      throw ArgumentError('Geçersiz yaş aralığı');
    }
    final prefs = await _prefs();
    if (enabled) {
      await _requireSaved(prefs.setInt(matchMinAgePrefKey, min));
      await _requireSaved(prefs.setInt(matchMaxAgePrefKey, max));
    } else {
      await _requireSaved(prefs.remove(matchMinAgePrefKey));
      await _requireSaved(prefs.remove(matchMaxAgePrefKey));
    }
  }

  Future<void> setCountryFilter(String value) async {
    final prefs = await _prefs();
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _requireSaved(prefs.remove(matchCountryFilterPrefKey));
    } else {
      if (normalized.length > 80) throw ArgumentError('Ülke filtresi çok uzun');
      await _requireSaved(
          prefs.setString(matchCountryFilterPrefKey, normalized));
    }
  }

  Future<void> setProximity(
      {required bool enabled, required int maxDistanceKm}) async {
    if (maxDistanceKm < 1 || maxDistanceKm > 200) {
      throw ArgumentError('Geçersiz mesafe');
    }
    final prefs = await _prefs();
    if (enabled) {
      await _requireSaved(
          prefs.setInt(matchMaxDistanceKmPrefKey, maxDistanceKm));
    } else {
      await _requireSaved(prefs.remove(matchMaxDistanceKmPrefKey));
    }
  }

  Future<void> setTextOnly(bool value) async {
    await _requireSaved((await _prefs()).setBool(matchTextOnlyPrefKey, value));
  }

  Future<void> setSpeedRound(bool value) async {
    await _requireSaved(
        (await _prefs()).setBool(matchSpeedRoundPrefKey, value));
  }

  Future<void> setRequireCommonInterest(bool value) async {
    await _requireSaved(
      (await _prefs()).setBool(matchRequireCommonInterestPrefKey, value),
    );
  }

  Future<void> _requireSaved(Future<bool> operation) async {
    if (!await operation) {
      throw StateError('Eşleşme tercihi cihazda kaydedilemedi.');
    }
  }
}
