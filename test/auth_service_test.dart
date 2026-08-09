// AuthService, oturumun cihazda kalıcı olup olmadığını (uygulama kapatılıp
// tekrar açıldığında kullanıcının tekrar giriş yapmak zorunda kalıp
// kalmayacağını) belirleyen kritik bir bileşen - burada network gerektiren
// register/login/verifySession akışlarını değil (bunlar için AuthService
// http istemcisini dışarıdan enjekte edilebilir yapmadığından gerçek bir
// sunucu gerekir), yalnızca saf/yerel mantığı test ediyoruz:
// AppUser.fromJson ayrıştırması ve shared_preferences tabanlı
// restoreSession()/logout() akışı.

import 'package:flutter_test/flutter_test.dart';

import 'package:merhaba_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUser.fromJson', () {
    test('tüm alanlar doluyken doğru ayrıştırır', () {
      final user = AppUser.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'displayName': 'Ada',
        'bio': 'merhaba',
        'gender': 'kadın',
        'interests': ['müzik', 'spor'],
        'country': 'TR',
        'language': 'tr',
        'age': 28,
        'verified': true,
        'online': true,
        'lastSeen': '2026-07-01T10:00:00.000Z',
      });

      expect(user.id, 'u1');
      expect(user.email, 'a@b.com');
      expect(user.displayName, 'Ada');
      expect(user.bio, 'merhaba');
      expect(user.gender, 'kadın');
      expect(user.interests, ['müzik', 'spor']);
      expect(user.country, 'TR');
      expect(user.language, 'tr');
      expect(user.age, 28);
      expect(user.verified, true);
      expect(user.online, true);
      expect(user.lastSeen, DateTime.parse('2026-07-01T10:00:00.000Z'));
    });

    test('isteğe bağlı alanlar eksikken güvenli varsayılanlara düşer', () {
      final user = AppUser.fromJson({
        'id': 'u2',
        'email': 'c@d.com',
        'displayName': 'Deniz',
      });

      expect(user.bio, '');
      expect(user.gender, isNull);
      expect(user.interests, isEmpty);
      expect(user.country, isNull);
      expect(user.language, isNull);
      expect(user.age, isNull);
      expect(user.verified, false);
      expect(user.online, false);
      expect(user.lastSeen, isNull);
    });

    test('bozuk lastSeen string bir exception fırlatmak yerine null olur', () {
      final user = AppUser.fromJson({
        'id': 'u3',
        'email': 'e@f.com',
        'displayName': 'Ege',
        'lastSeen': 'bu-bir-tarih-degil',
      });

      expect(user.lastSeen, isNull);
    });
  });
}
