import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/adult_age_policy.dart';

void main() {
  final now = DateTime(2026, 8, 3);

  test('18. doğum gününde yetişkin kabul edilir', () {
    expect(AdultAgePolicy.ageOn(DateTime(2008, 8, 3), now), 18);
    expect(AdultAgePolicy.isAdult(DateTime(2008, 8, 3), now), isTrue);
  });

  test('18. doğum gününden bir gün önce reddedilir', () {
    expect(AdultAgePolicy.ageOn(DateTime(2008, 8, 4), now), 17);
    expect(AdultAgePolicy.isAdult(DateTime(2008, 8, 4), now), isFalse);
  });

  test('API tarihi sıfır dolgulu üretilir', () {
    expect(AdultAgePolicy.toApiDate(DateTime(1995, 2, 7)), '1995-02-07');
  });
}
