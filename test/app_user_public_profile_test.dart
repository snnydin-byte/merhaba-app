import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/models/app_user.dart';

void main() {
  test('public profile can omit the private email field', () {
    final user = AppUser.fromJson({
      'id': 'u-public',
      'displayName': 'Derya',
    });

    expect(user.email, '');
    expect(user.displayName, 'Derya');
  });
}
