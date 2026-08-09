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
  final bool ageVerified;
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
    this.ageVerified = false,
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
        // Sunucu, başka bir kullanıcının herkese açık profilinde e-posta
        // adresini bilerek göndermez. Keşfet/eşleşme profilleri bu yüzden
        // `email` alanı olmadan da güvenle ayrıştırılabilmelidir.
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String,
        bio: json['bio'] as String? ?? '',
        gender: json['gender'] as String?,
        interests: (json['interests'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        country: json['country'] as String?,
        language: json['language'] as String?,
        age: json['age'] as int?,
        ageVerified: json['ageVerified'] as bool? ?? false,
        verified: json['verified'] as bool? ?? false,
        online: json['online'] as bool? ?? false,
        lastSeen: json['lastSeen'] != null
            ? DateTime.tryParse(json['lastSeen'] as String)
            : null,
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
                ?.map((e) => TrustedContact.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        profileBadges: (json['profileBadges'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        selfieVerified: json['selfieVerified'] as bool? ?? false,
        selfieVerificationStatus:
            json['selfieVerificationStatus'] as String? ?? 'none',
        isBoosted: json['isBoosted'] as bool? ?? false,
        discoverInvisible: json['discoverInvisible'] as bool? ?? false,
        compatibilityAnswers:
            (json['compatibilityAnswers'] as Map<String, dynamic>?)
                    ?.map((k, v) => MapEntry(k, v as int)) ??
                const {},
        level: json['level'] as int? ?? 1,
        xp: json['xp'] as int? ?? 0,
        avatarConfig: json['avatarConfig'] != null
            ? AvatarConfig.fromJson(
                Map<String, dynamic>.from(json['avatarConfig'] as Map))
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
        ageVerified: ageVerified,
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

  Map<String, dynamic> toJson() =>
      {'backgroundColor': backgroundColor, 'emoji': emoji};
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
