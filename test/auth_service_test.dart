// AuthService, oturumun cihazda kalıcı olup olmadığını (uygulama kapatılıp
// tekrar açıldığında kullanıcının tekrar giriş yapmak zorunda kalıp
// kalmayacağını) belirleyen kritik bir bileşen - burada network gerektiren
// register/login/verifySession akışlarını değil (bunlar için AuthService
// http istemcisini dışarıdan enjekte edilebilir yapmadığından gerçek bir
// sunucu gerekir), yalnızca saf/yerel mantığı test ediyoruz:
// AppUser.fromJson ayrıştırması ve shared_preferences tabanlı
// restoreSession()/logout() akışı.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('AuthService oturum kalıcılığı', () {
    setUp(() async {
      // Her testten önce hem shared_preferences'ı hem de singleton'ın
      // bellek-içi durumunu temizliyoruz - AuthService bir singleton
      // olduğu için testler arasında sızıntı olmasını (bir testin
      // diğerini etkilemesini) önlemek için şart.
      SharedPreferences.setMockInitialValues({});
      await AuthService().logout();
    });

    test('hiç kayıtlı oturum yoksa restoreSession false döner', () async {
      final restored = await AuthService().restoreSession();
      expect(restored, false);
      expect(AuthService().isLoggedIn, false);
    });

    test('kayıtlı oturum varsa restoreSession true döner ve kullanıcıyı doldurur', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'test-token-123',
        'auth_user_id': 'u1',
        'auth_user_email': 'a@b.com',
        'auth_user_name': 'Ada',
      });

      final restored = await AuthService().restoreSession();

      expect(restored, true);
      expect(AuthService().isLoggedIn, true);
      expect(AuthService().token, 'test-token-123');
      expect(AuthService().currentUser?.id, 'u1');
      expect(AuthService().currentUser?.displayName, 'Ada');
    });

    test('kayıtlı alanlardan biri eksikse oturum geri yüklenmez (yarım/bozuk veri)', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'test-token-123',
        'auth_user_id': 'u1',
        // auth_user_email kasıtlı olarak eksik
        'auth_user_name': 'Ada',
      });

      final restored = await AuthService().restoreSession();

      expect(restored, false);
      expect(AuthService().isLoggedIn, false);
    });

    test('logout hem bellek-içi durumu hem de saklanan oturumu temizler', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'test-token-123',
        'auth_user_id': 'u1',
        'auth_user_email': 'a@b.com',
        'auth_user_name': 'Ada',
      });
      await AuthService().restoreSession();
      expect(AuthService().isLoggedIn, true);

      await AuthService().logout();

      expect(AuthService().isLoggedIn, false);
      expect(AuthService().token, isNull);
      expect(AuthService().currentUser, isNull);

      // Oturum bilgisi gerçekten diskten de silinmiş mi - yeni bir
      // restoreSession() artık false dönmeli.
      final restoredAgain = await AuthService().restoreSession();
      expect(restoredAgain, false);
    });
  });
}
