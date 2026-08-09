class AdultAgePolicy {
  AdultAgePolicy._();

  static const int minimumAge = 18;
  static const int maximumAge = 120;

  static DateTime latestEligibleBirthDate([DateTime? now]) {
    final current = now ?? DateTime.now();
    return DateTime(current.year - minimumAge, current.month, current.day);
  }

  static DateTime earliestEligibleBirthDate([DateTime? now]) {
    final current = now ?? DateTime.now();
    return DateTime(current.year - maximumAge, current.month, current.day);
  }

  static int ageOn(DateTime birthDate, [DateTime? now]) {
    final current = now ?? DateTime.now();
    var age = current.year - birthDate.year;
    final birthdayPassed = current.month > birthDate.month ||
        (current.month == birthDate.month && current.day >= birthDate.day);
    if (!birthdayPassed) age--;
    return age;
  }

  static bool isAdult(DateTime birthDate, [DateTime? now]) {
    final age = ageOn(birthDate, now);
    return age >= minimumAge && age <= maximumAge;
  }

  static String toApiDate(DateTime birthDate) {
    return '${birthDate.year.toString().padLeft(4, '0')}-'
        '${birthDate.month.toString().padLeft(2, '0')}-'
        '${birthDate.day.toString().padLeft(2, '0')}';
  }

  static String displayDate(DateTime birthDate) {
    return '${birthDate.day.toString().padLeft(2, '0')}.'
        '${birthDate.month.toString().padLeft(2, '0')}.'
        '${birthDate.year}';
  }
}
