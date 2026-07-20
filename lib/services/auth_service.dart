import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'webrtc_service.dart' show signalingServerUrl;

// Google ile hızlı kayıt (Batch C) - bu, Google Cloud Console'da OTOMATİK
// oluşan "Web client (auto created by Google Service)" OAuth istemcisinin
// ID'si. GİZLİ bir değer DEĞİL (apiKey gibi - istemci koduna gömülmesi
// normal, bkz. firebase_options.dart'taki aynı yaklaşım) ama Sinan'ın
// Firebase konsolunda "Authentication > Sign-in method > Google" sağlayıcısını
// AÇMASI ve oradan bu değeri kopyalayıp buraya yapıştırması gerekiyor -
// kurulum adımları KURULUM.md'de. Ayarlanana kadar bu placeholder ile kalır
// ve Google ile giriş düğmesi gösterilmez (bkz. isGoogleSignInConfigured) -
// firebase_options.dart'taki _placeholderApiKey deseniyle AYNI "zarif geri
// düşme" (istemci tarafı gösterilmiyor, sunucu tarafı da GOOGLE_WEB_CLIENT_ID
// ayarlanmadıysa 503 döner, hiçbir yerde çökme olmaz).
const String _googleWebClientId =
    '237640279761-pov3sop9c2fjmfc2ooe75lsnpti7e1ra.apps.googleusercontent.com';

bool get isGoogleSignInConfigured =>
    !_googleWebClientId.startsWith('REPLACE_WITH_');

/// Sinyalleşme sunucusundaki bir hesabı temsil eder (bkz.
/// signaling_server/userStore.js publicUser()). Şifre burada tutulmaz.
class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String bio;
  final String? gender; // 'erkek' | 'kadın' | null (belirtilmemiş)
  final List<String> interests;
  final String? country;
  final String? language;
  final int? age;
  final bool verified;
  final bool online;
  final DateTime? lastSeen;
  final String? photoUrl;
  // Yalnızca kendi profilini çekerken sunucudan dolu gelir (bkz. server.js
  // publicUser() - `isSelf` değilse bu 3 alan undefined/null döner, JSON'a
  // hiç girmez). #39/#24 anket maddeleri.
  final bool hideOnlineStatus;
  final bool hideLastSeen;
  final bool readReceiptsEnabled;
  // Batch C eşleştirme motoru genişletmeleri.
  // birthDate: yalnızca kendi profilini çekerken dolu gelir (bkz.
  // server.js publicUser() - hassas kişisel veri, başkalarına gösterilmez).
  final String? birthDate; // "YYYY-MM-DD"
  final String? zodiac; // sunucuda türetilir, herkese görünür
  final String? introVideoUrl;
  final bool isPremium;
  // Günlük giriş serisi (GECE_GELISTIRME madde 7) - yalnızca kendi profilinde
  // dolu gelir (bkz. server.js publicUser()), saf görsel bir rozet.
  final int loginStreak;
  // Eşleşme (Dating) katmanı - Batch E. profileBadges/selfieVerified/
  // isBoosted HERKESE görünür. discoverInvisible/compatibilityAnswers
  // yalnızca kendi profilinde dolu gelir (bkz. server.js publicUser()).
  final List<String> closeFriendIds;
  final List<TrustedContact> trustedContacts;
  final List<String> profileBadges;
  final bool selfieVerified;
  // 'none' | 'pending' | 'approved' | 'rejected' - yalnızca kendi profilinde
  // dolu (bkz. server.js publicUser()).
  final String selfieVerificationStatus;
  final bool isBoosted;
  final bool discoverInvisible;
  final Map<String, int> compatibilityAnswers;
  // Sosyal/Oyunlaştırma (Batch G) - level/xp/avatarConfig HERKESE görünür,
  // achievementIds de öyle (bir profildeki kazanılmış rozetler gibi).
  final int level;
  final int xp;
  final AvatarConfig? avatarConfig;
  final List<String> achievementIds;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.bio = '',
    this.gender,
    this.interests = const [],
    this.country,
    this.language,
    this.age,
    this.verified = false,
    this.online = false,
    this.lastSeen,
    this.photoUrl,
    this.hideOnlineStatus = false,
    this.hideLastSeen = false,
    this.readReceiptsEnabled = true,
    this.birthDate,
    this.zodiac,
    this.introVideoUrl,
    this.isPremium = false,
    this.loginStreak = 0,
    this.closeFriendIds = const [],
    this.trustedContacts = const [],
    this.level = 1,
    this.xp = 0,
    this.avatarConfig,
    this.achievementIds = const [],
    this.profileBadges = const [],
    this.selfieVerified = false,
    this.selfieVerificationStatus = 'none',
    this.isBoosted = false,
    this.discoverInvisible = false,
    this.compatibilityAnswers = const {},
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        bio: json['bio'] as String? ?? '',
        gender: json['gender'] as String?,
        interests: (json['interests'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        country: json['country'] as String?,
        language: json['language'] as String?,
        age: json['age'] as int?,
        verified: json['verified'] as bool? ?? false,
        online: json['online'] as bool? ?? false,
        lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen'] as String) : null,
        // Sunucu (bkz. signaling_server/server.js publicUser()) fotoğraf
        // varsa kendi GET /avatars/:userId ucuna işaret eden tam bir URL
        // döner, yoksa null - foto yoksa ekranlar isim baş harfini gösterir.
        photoUrl: json['photoUrl'] as String?,
        hideOnlineStatus: json['hideOnlineStatus'] as bool? ?? false,
        hideLastSeen: json['hideLastSeen'] as bool? ?? false,
        readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
        birthDate: json['birthDate'] as String?,
        zodiac: json['zodiac'] as String?,
        introVideoUrl: json['introVideoUrl'] as String?,
        isPremium: json['isPremium'] as bool? ?? false,
        loginStreak: json['loginStreak'] as int? ?? 0,
        closeFriendIds: (json['closeFriendIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        trustedContacts: (json['trustedContacts'] as List<dynamic>?)
                ?.map((e) => TrustedContact.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        profileBadges: (json['profileBadges'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        selfieVerified: json['selfieVerified'] as bool? ?? false,
        selfieVerificationStatus: json['selfieVerificationStatus'] as String? ?? 'none',
        isBoosted: json['isBoosted'] as bool? ?? false,
        discoverInvisible: json['discoverInvisible'] as bool? ?? false,
        compatibilityAnswers: (json['compatibilityAnswers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as int)) ??
            const {},
        level: json['level'] as int? ?? 1,
        xp: json['xp'] as int? ?? 0,
        avatarConfig: json['avatarConfig'] != null
            ? AvatarConfig.fromJson(Map<String, dynamic>.from(json['avatarConfig'] as Map))
            : null,
        achievementIds: (json['achievementIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  AppUser copyWith({List<String>? closeFriendIds}) => AppUser(
        id: id,
        email: email,
        displayName: displayName,
        bio: bio,
        gender: gender,
        interests: interests,
        country: country,
        language: language,
        age: age,
        verified: verified,
        online: online,
        lastSeen: lastSeen,
        photoUrl: photoUrl,
        hideOnlineStatus: hideOnlineStatus,
        hideLastSeen: hideLastSeen,
        readReceiptsEnabled: readReceiptsEnabled,
        birthDate: birthDate,
        zodiac: zodiac,
        introVideoUrl: introVideoUrl,
        isPremium: isPremium,
        loginStreak: loginStreak,
        closeFriendIds: closeFriendIds ?? this.closeFriendIds,
        trustedContacts: trustedContacts,
        profileBadges: profileBadges,
        selfieVerified: selfieVerified,
        selfieVerificationStatus: selfieVerificationStatus,
        isBoosted: isBoosted,
        discoverInvisible: discoverInvisible,
        compatibilityAnswers: compatibilityAnswers,
        level: level,
        xp: xp,
        avatarConfig: avatarConfig,
        achievementIds: achievementIds,
      );
}

/// Avatar oluşturucu (Batch G) - gerçek bir illüstrasyon sistemi DEĞİL,
/// yalnızca renk+emoji (bkz. server.js doğrulaması: hex renk + tek emoji).
class AvatarConfig {
  final String backgroundColor;
  final String emoji;
  const AvatarConfig({required this.backgroundColor, required this.emoji});

  factory AvatarConfig.fromJson(Map<String, dynamic> json) => AvatarConfig(
        backgroundColor: json['backgroundColor'] as String,
        emoji: json['emoji'] as String,
      );

  Map<String, dynamic> toJson() => {'backgroundColor': backgroundColor, 'emoji': emoji};
}

/// Güvenilir kişi (Batch F) - gerçek bir hesap DEĞİL, yalnızca isim+telefon.
/// Panik butonu/buluşma detayı paylaşma bunları SMS ile ulaşmak için kullanır.
class TrustedContact {
  final String name;
  final String phone;
  const TrustedContact({required this.name, required this.phone});

  factory TrustedContact.fromJson(Map<String, dynamic> json) => TrustedContact(
        name: json['name'] as String,
        phone: json['phone'] as String,
      );

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

/// Sunucudan dönen kullanıcıya-gösterilebilir bir hata (ör. "şifre en az 6
/// karakter olmalı", "e-posta veya şifre hatalı").
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

/// Uygulamanın kimlik doğrulama durumunu ve sinyalleşme sunucusundaki
/// /auth/* + /profile uçlarıyla haberleşmeyi yönetir.
///
/// Oturum bilgisi (token + kullanıcı) cihazda shared_preferences ile
/// saklanır. Token bir JWT olduğu için doğrulaması sunucu tarafında
/// durumsuz (stateless) yapılır - sunucu yeniden başlatılsa bile (ki
/// geliştirme sırasında sık olur, users.json'a yazıldığı için veri
/// kaybolmaz) token geçerliliğini korur.
///
/// Basit bir singleton: uygulama boyunca tek bir örnek kullanılır ki
/// splash/login/home/profile ekranları aynı oturum durumunu görsün.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _userEmailKey = 'auth_user_email';
  static const _userNameKey = 'auth_user_name';

  String? _token;
  AppUser? _currentUser;

  String? get token => _token;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _token != null && _currentUser != null;

  /// Cihazda daha önce saklanmış bir oturum var mı diye bakar (sunucuya
  /// gitmeden). Splash ekranında sunucuya sormadan önce hızlı bir "muhtemelen
  /// giriş yapılmış" durumu vermek için kullanılır.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userId = prefs.getString(_userIdKey);
    final email = prefs.getString(_userEmailKey);
    final name = prefs.getString(_userNameKey);
    if (token == null || userId == null || email == null || name == null) {
      return false;
    }
    _token = token;
    _currentUser = AppUser(id: userId, email: email, displayName: name);
    return true;
  }

  /// Sunucudan /auth/me çağırarak token'ın hâlâ geçerli olduğunu ve
  /// kullanıcı bilgisinin güncel olduğunu doğrular.
  ///
  /// Sunucuya ulaşılamazsa (ör. kapalıysa) oturumu KAPATMAZ - kullanıcıyı
  /// yalnızca sunucu o an ayaktayken atılamadığı için dışarı atmamak adına
  /// cihazdaki bilgiyle devam edilir. Sunucu token'ı gerçekten geçersiz
  /// (401) bulursa çıkış yapılır.
  Future<bool> verifySession() async {
    if (_token == null) return false;
    try {
      final response = await http.get(
        Uri.parse('$signalingServerUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
        await _persist();
        return true;
      }
      if (response.statusCode == 401) {
        await logout();
        return false;
      }
      return true;
    } catch (_) {
      // Sunucuya ulaşılamıyor (ör. henüz başlatılmadı) - cihazdaki oturumla devam.
      return true;
    }
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _post('/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    return _applyAuthResponse(response);
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final response = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    return _applyAuthResponse(response);
  }

  /// Google ile kayıt/giriş (Batch C). google_sign_in paketi kullanıcıya
  /// yerleşik Google hesap seçici diyaloğunu gösterir, biz yalnızca dönen
  /// imzalı ID token'ı sunucuya iletip (bkz. server.js POST /auth/google)
  /// normal JWT oturum akışına geçeriz - şifre hiçbir zaman bu uygulamaya
  /// veya sunucusuna gelmez.
  ///
  /// [isGoogleSignInConfigured] false ise (Sinan henüz Firebase konsolunda
  /// Google sağlayıcısını açıp gerçek client ID'yi yapıştırmadıysa) çağıran
  /// ekran bu düğmeyi hiç GÖSTERMEMELİ - yine de çağrılırsa erken bir
  /// AuthException fırlatılır.
  ///
  /// Kullanıcı hesap seçiciyi iptal ederse hata FIRLATILMAZ, null döner -
  /// çağıran ekran bunu sessizce (hata mesajı göstermeden) ele almalı.
  Future<AppUser?> signInWithGoogle() async {
    if (!isGoogleSignInConfigured) {
      throw AuthException('Google ile giriş şu an yapılandırılmamış.');
    }

    final googleSignIn = GoogleSignIn(serverClientId: _googleWebClientId);
    GoogleSignInAccount? account;
    try {
      account = await googleSignIn.signIn();
    } catch (_) {
      throw AuthException('Google ile giriş başlatılamadı, tekrar dene.');
    }
    if (account == null) return null;

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw AuthException('Google kimlik doğrulaması eksik döndü, tekrar dene.');
    }

    final response = await _post('/auth/google', {'idToken': idToken});
    return _applyAuthResponse(response);
  }

  Future<void> updateDisplayName(String displayName) async {
    await updateProfile(displayName: displayName);
  }

  /// Profil alanlarını günceller. [displayName] verilmezse mevcut isim
  /// korunur (sunucu her zaman bir isim bekliyor). Diğer alanlardan
  /// yalnızca verilenler değiştirilir - null geçilen bir alan sunucu
  /// tarafında olduğu gibi bırakılır (bkz. userStore.updateProfileFields).
  /// Bir alanı BOŞALTMAK için (ör. cinsiyeti kaldırmak) o alana açıkça
  /// null yerine boş string/uygun "temizle" değeri geçmek gerekir - bio
  /// için boş string, gender/country/language için null zaten "değiştirme"
  /// anlamına geldiğinden bu üçünü temizlemek şu an desteklenmiyor.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? gender,
    List<String>? interests,
    String? country,
    String? language,
    int? age,
    bool? hideOnlineStatus,
    bool? hideLastSeen,
    bool? readReceiptsEnabled,
    String? birthDate,
    bool? discoverInvisible,
    List<String>? profileBadges,
    Map<String, int>? compatibilityAnswers,
    AvatarConfig? avatarConfig,
    bool clearAvatarConfig = false,
  }) async {
    if (_token == null) throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');

    final body = <String, dynamic>{
      'displayName': displayName ?? _currentUser?.displayName ?? '',
    };
    if (bio != null) body['bio'] = bio;
    if (gender != null) body['gender'] = gender;
    if (interests != null) body['interests'] = interests;
    if (country != null) body['country'] = country;
    if (language != null) body['language'] = language;
    if (age != null) body['age'] = age;
    if (hideOnlineStatus != null) body['hideOnlineStatus'] = hideOnlineStatus;
    if (hideLastSeen != null) body['hideLastSeen'] = hideLastSeen;
    if (readReceiptsEnabled != null) body['readReceiptsEnabled'] = readReceiptsEnabled;
    if (birthDate != null) body['birthDate'] = birthDate;
    if (discoverInvisible != null) body['discoverInvisible'] = discoverInvisible;
    if (profileBadges != null) body['profileBadges'] = profileBadges;
    if (compatibilityAnswers != null) body['compatibilityAnswers'] = compatibilityAnswers;
    if (avatarConfig != null) {
      body['avatarConfig'] = avatarConfig.toJson();
    } else if (clearAvatarConfig) {
      body['avatarConfig'] = null;
    }

    final http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('$signalingServerUrl/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun çalıştığından emin ol.');
    }

    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  /// Profil fotoğrafını yükler/değiştirir. Sunucu bunu Firebase Storage'a
  /// kaydeder (bkz. signaling_server/photoStorage.js) - burada yalnızca
  /// dosyayı multipart/form-data ile gönderiyoruz. Var olan fotoğraf varsa
  /// sunucu tarafında otomatik olarak üzerine yazılır (bkz. photoStorage.js
  /// uploadAvatar - sabit dosya adı kullanır).
  Future<void> uploadProfilePhoto(File file) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }

    final request =
        http.MultipartRequest('POST', Uri.parse('$signalingServerUrl/profile/photo'))
          ..headers['Authorization'] = 'Bearer $_token'
          ..files.add(await http.MultipartFile.fromPath('photo', file.path));

    final http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Fotoğraf yüklenemedi, tekrar dene.');
    }

    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  /// Profil fotoğrafını kaldırır - ekranlar tekrar isim baş harfini gösterir.
  Future<void> removeProfilePhoto() async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }

    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$signalingServerUrl/profile/photo'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException('Sunucuya ulaşılamıyor. Tekrar dene.');
    }

    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  /// Video profil tanıtımı yükler (Batch C) - kısa bir klip, chat medyası
  /// gibi Cloudinary'ye gidiyor (bkz. server.js POST /profile/intro-video).
  Future<void> uploadIntroVideo(File file) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final request =
        http.MultipartRequest('POST', Uri.parse('$signalingServerUrl/profile/intro-video'))
          ..headers['Authorization'] = 'Bearer $_token'
          ..files.add(await http.MultipartFile.fromPath('video', file.path));

    final http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw AuthException('Sunucuya ulaşılamıyor. Video yüklenemedi, tekrar dene.');
    }

    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  Future<void> removeIntroVideo() async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$signalingServerUrl/profile/intro-video'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  /// Selfie doğrulama rozeti (Batch E) - fotoğraf Cloudinary'ye yüklenir,
  /// onay AI DEĞİL, Sinan'ın manuel admin incelemesiyle olur (bkz.
  /// server.js GET/POST /admin/selfie-verifications). Yükleme sonrası
  /// `user.selfieVerificationStatus` 'pending' olur.
  Future<void> uploadSelfieVerification(File file) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final request =
        http.MultipartRequest('POST', Uri.parse('$signalingServerUrl/profile/selfie-verification'))
          ..headers['Authorization'] = 'Bearer $_token'
          ..files.add(await http.MultipartFile.fromPath('photo', file.path));

    final http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw AuthException('Sunucuya ulaşılamıyor. Fotoğraf yüklenemedi, tekrar dene.');
    }

    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  /// Hesabı sunucudan kalıcı olarak siler (geri alınamaz) ve ardından yerel
  /// oturumu temizler. Çağıran taraf (Ayarlar ekranı) bu metottan önce
  /// kullanıcıya bir onay diyaloğu göstermeli.
  Future<void> deleteAccount() async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }

    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$signalingServerUrl/profile'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun çalıştığından emin ol.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Hesap silinemedi, tekrar dene.';
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        message = data['error'] as String? ?? message;
      } catch (_) {
        // Yanıt JSON değilse varsayılan mesajı kullan.
      }
      throw AuthException(message);
    }

    await logout();
  }

  /// Bir arkadaşı şikayet eder (bkz. signaling_server/reportStore.js
  /// VALID_REASONS - [reason] bunlardan biri olmalı: 'uygunsuz-goruntu',
  /// 'taciz', 'kucuk-yasta' (reşit olmayan biri gibi görünüyor), 'spam',
  /// 'sahte-hesap', 'diger'). Şikayet sunucuda saklanır - bu metot ayrıca
  /// engelleme/arkadaşlıktan çıkarma YAPMAZ, çağıran ekran isterse bunu
  /// ayrıca (kendi akışıyla) başlatır.
  Future<void> reportFriend(String friendId, String reason, {String? note}) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$signalingServerUrl/friends/$friendId/report'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode({
              'reason': reason,
              if (note != null) 'note': note,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Şikayet gönderilemedi, tekrar dene.');
    }

    _decodeOrThrow(response);
  }

  /// Gerçek zamanlı mesaj çevirisi (GECE_GELISTIRME madde 5) - sunucu
  /// TRANSLATE_API_KEY ile yapılandırılmadıysa 503 döner (bkz.
  /// translationService.js), bu durumda AuthException fırlatılır ve çağıran
  /// ekran (chat_screen.dart) kullanıcıya "çeviri şu an yapılandırılmamış"
  /// gibi bir mesaj gösterir.
  Future<String> translateText(String text, String targetLang) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final response = await _post('/translate', {'text': text, 'targetLang': targetLang});
    final data = _decodeOrThrow(response);
    return data['translatedText'] as String? ?? text;
  }

  /// Kısıtlı liste / yakın arkadaşlar (Batch F) - toggle, yalnızca
  /// ARKADAŞLAR arasından seçilebilir (sunucu tarafında da kontrol edilir).
  Future<void> toggleCloseFriend(String friendId) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$signalingServerUrl/friends/$friendId/close-friend'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    final data = _decodeOrThrow(response);
    final ids = (data['closeFriendIds'] as List<dynamic>).map((e) => e.toString()).toList();
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(closeFriendIds: ids);
    }
  }

  /// Güvenilir kişiler listesini günceller (Batch F) - en fazla 5, sunucu
  /// tarafında da kırpılır (bkz. userStore.setTrustedContacts).
  Future<void> updateTrustedContacts(List<TrustedContact> contacts) async {
    if (_token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final http.Response response;
    try {
      response = await http
          .put(
            Uri.parse('$signalingServerUrl/profile/trusted-contacts'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode({'contacts': contacts.map((c) => c.toJson()).toList()}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    final data = _decodeOrThrow(response);
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userNameKey);
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await http
          .post(
            Uri.parse('$signalingServerUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun (signaling_server) '
          'çalıştığından ve doğru adrese ayarlandığından emin ol.');
    }
  }

  Future<AppUser> _applyAuthResponse(http.Response response) async {
    final data = _decodeOrThrow(response);
    _token = data['token'] as String;
    _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
    return _currentUser!;
  }

  Map<String, dynamic> _decodeOrThrow(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException('Sunucudan beklenmeyen bir yanıt geldi.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(data['error'] as String? ?? 'Bir şeyler ters gitti.');
    }
    return data;
  }

  Future<void> _persist() async {
    if (_token == null || _currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userIdKey, _currentUser!.id);
    await prefs.setString(_userEmailKey, _currentUser!.email);
    await prefs.setString(_userNameKey, _currentUser!.displayName);
  }
}
