import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/messaging_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import '../utils/text_scale_notifier.dart';
import 'login_screen.dart';
import 'trusted_contacts_screen.dart';

// GitHub Pages üzerinde barındırılan statik sayfalar (bkz. proje kökündeki
// docs/ klasörü). Play Store yayını öncesi GERÇEK içerikle
// (docs/privacy.html, docs/community-rules.html) doldurulup GitHub
// Pages'te yayınlanmış olmaları gerekiyor - bkz. KURULUM.md "Play Store
// Yayın Hazırlığı" bölümü.
const String privacyPolicyUrl =
    'https://snnydin-byte.github.io/merhaba-app/privacy.html';
const String communityRulesUrl =
    'https://snnydin-byte.github.io/merhaba-app/community-rules.html';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _notificationsPrefKey = 'notifications_enabled';

  bool _notifications = true;
  bool _loadingPrefs = true;
  bool _deletingAccount = false;
  // pubspec.yaml'daki gerçek sürüm numarasını okuyoruz - önceden burada
  // elle yazılmış, güncel olmayabilecek "1.0.0 (Demo)" gibi sabit bir metin
  // vardı; yayınlanmış bir uygulamada sürüm numarası derleme zamanında
  // otomatik ve doğru olmalı, elle senkronize edilmemeli.
  String _appVersion = '';

  // Bu üç filtre artık GERÇEK: sunucu tarafındaki tryMatch()/
  // findEligiblePartnerIndex() bunları uyguluyor (bkz. server.js
  // passesGenderFilter/passesAgeFilter/passesVerifiedFilter). Burada
  // SharedPreferences'a kaydediyoruz, webrtc_service.dart'taki
  // loadMatchPreferences() aynı anahtarları okuyup find-match ile sunucuya
  // gönderiyor.
  String _genderFilter = 'herkes'; // 'herkes' | 'erkek' | 'kadın'
  RangeValues _ageRange = const RangeValues(18, 60);
  bool _ageRangeEnabled = false;
  bool _onlyVerified = false;

  // Batch C eşleştirme motoru genişletmeleri.
  final _countryFilterController = TextEditingController();
  bool _proximityEnabled = false;
  double _maxDistanceKm = 100;
  bool _textOnlyMode = false;
  bool _speedRoundMode = false;
  // GECE_GELISTIRME madde 4 - ilgi alanı etiketiyle eşleştirme (sert filtre,
  // affinityScore'daki YUMUŞAK ilgi alanı önceliğinden AYRI - o zaten her
  // eşleşmede otomatik çalışıyor, bu anahtar "yalnızca ortak ilgi alanım
  // olanlarla eşleş" gibi daha katı bir tercih).
  bool _requireCommonInterest = false;

  // Eşleşme (Dating) katmanı - Batch E. discoverInvisible SUNUCUDA hesaba
  // bağlı (SharedPreferences DEĞİL - hideOnlineStatus/hideLastSeen ile AYNI
  // desen), o yüzden _loadPrefs()'te değil kullanıcı yüklenince ayarlanıyor.
  bool _discoverInvisible = false;

  // Gizlilik ayarları (#39/#24 anket maddeleri) - SharedPreferences DEĞİL,
  // sunucuda hesaba bağlı olarak saklanır (bkz. AuthService.updateProfile).
  // Misafir kullanıcılarda hiç hesap olmadığı için bu anahtarlar devre dışı.
  bool _hideOnlineStatus = false;
  bool _hideLastSeen = false;
  bool _readReceiptsEnabled = true;
  bool _savingPrivacy = false;

  static const _genderLabels = {
    'herkes': 'Herkes',
    'erkek': 'Erkek',
    'kadın': 'Kadın'
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadAppVersion();
  }

  @override
  void dispose() {
    _countryFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // Sessizce yok say - versiyon bilgisi gösterilemezse ekranın geri
      // kalanı yine de düzgün çalışmaya devam etmeli.
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final minAge = prefs.getInt(matchMinAgePrefKey);
    final maxAge = prefs.getInt(matchMaxAgePrefKey);
    setState(() {
      _notifications = prefs.getBool(_notificationsPrefKey) ?? true;
      _genderFilter = prefs.getString(matchGenderFilterPrefKey) ?? 'herkes';
      _ageRangeEnabled = minAge != null || maxAge != null;
      _ageRange = RangeValues(
        (minAge ?? 18).toDouble(),
        (maxAge ?? 60).toDouble(),
      );
      _onlyVerified = prefs.getBool(matchOnlyVerifiedPrefKey) ?? false;
      _countryFilterController.text =
          prefs.getString(matchCountryFilterPrefKey) ?? '';
      final maxDistanceKm = prefs.getInt(matchMaxDistanceKmPrefKey);
      _proximityEnabled = maxDistanceKm != null;
      _maxDistanceKm = (maxDistanceKm ?? 100).toDouble();
      _textOnlyMode = prefs.getBool(matchTextOnlyPrefKey) ?? false;
      _speedRoundMode = prefs.getBool(matchSpeedRoundPrefKey) ?? false;
      _requireCommonInterest =
          prefs.getBool(matchRequireCommonInterestPrefKey) ?? false;
      final user = AuthService().currentUser;
      if (user != null) {
        _hideOnlineStatus = user.hideOnlineStatus;
        _hideLastSeen = user.hideLastSeen;
        _readReceiptsEnabled = user.readReceiptsEnabled;
        _discoverInvisible = user.discoverInvisible;
      }
      _loadingPrefs = false;
    });
  }

  Future<void> _setHideOnlineStatus(bool value) async {
    setState(() => _hideOnlineStatus = value);
    await _savePrivacyField(hideOnlineStatus: value);
  }

  Future<void> _setHideLastSeen(bool value) async {
    setState(() => _hideLastSeen = value);
    await _savePrivacyField(hideLastSeen: value);
  }

  Future<void> _setReadReceiptsEnabled(bool value) async {
    setState(() => _readReceiptsEnabled = value);
    await _savePrivacyField(readReceiptsEnabled: value);
  }

  Future<void> _setDiscoverInvisible(bool value) async {
    setState(() => _discoverInvisible = value);
    await _savePrivacyField(discoverInvisible: value);
  }

  Future<void> _savePrivacyField(
      {bool? hideOnlineStatus,
      bool? hideLastSeen,
      bool? readReceiptsEnabled,
      bool? discoverInvisible}) async {
    setState(() => _savingPrivacy = true);
    try {
      await AuthService().updateProfile(
        hideOnlineStatus: hideOnlineStatus,
        hideLastSeen: hideLastSeen,
        readReceiptsEnabled: readReceiptsEnabled,
        discoverInvisible: discoverInvisible,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayar kaydedilemedi, tekrar dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPrivacy = false);
    }
  }

  Future<void> _setNotifications(bool value) async {
    setState(() => _notifications = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsPrefKey, value);
  }

  Future<void> _setGenderFilter(String? value) async {
    if (value == null) return;
    setState(() => _genderFilter = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(matchGenderFilterPrefKey, value);
  }

  Future<void> _setOnlyVerified(bool value) async {
    setState(() => _onlyVerified = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(matchOnlyVerifiedPrefKey, value);
  }

  Future<void> _setAgeRangeEnabled(bool value) async {
    setState(() => _ageRangeEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setInt(matchMinAgePrefKey, _ageRange.start.round());
      await prefs.setInt(matchMaxAgePrefKey, _ageRange.end.round());
    } else {
      await prefs.remove(matchMinAgePrefKey);
      await prefs.remove(matchMaxAgePrefKey);
    }
  }

  Future<void> _setAgeRange(RangeValues values) async {
    setState(() => _ageRange = values);
    if (!_ageRangeEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(matchMinAgePrefKey, values.start.round());
    await prefs.setInt(matchMaxAgePrefKey, values.end.round());
  }

  Future<void> _setCountryFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(matchCountryFilterPrefKey);
    } else {
      await prefs.setString(matchCountryFilterPrefKey, trimmed);
    }
  }

  Future<void> _setProximityEnabled(bool value) async {
    setState(() => _proximityEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setInt(matchMaxDistanceKmPrefKey, _maxDistanceKm.round());
    } else {
      await prefs.remove(matchMaxDistanceKmPrefKey);
    }
  }

  Future<void> _setMaxDistanceKm(double value) async {
    setState(() => _maxDistanceKm = value);
    if (!_proximityEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(matchMaxDistanceKmPrefKey, value.round());
  }

  Future<void> _setTextOnlyMode(bool value) async {
    setState(() => _textOnlyMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(matchTextOnlyPrefKey, value);
  }

  Future<void> _setSpeedRoundMode(bool value) async {
    setState(() => _speedRoundMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(matchSpeedRoundPrefKey, value);
  }

  Future<void> _setRequireCommonInterest(bool value) async {
    setState(() => _requireCommonInterest = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(matchRequireCommonInterestPrefKey, value);
  }

  Future<void> _handleDeleteAccountTap() async {
    final authService = AuthService();

    if (!authService.isLoggedIn) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Silinecek hesap yok',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            'Şu an misafir olarak geziniyorsun, silinecek bir hesabın yok.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title:
            Text('Hesabı sil', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Bu işlem geri alınamaz. Hesabın ve profil bilgilerin sunucudan '
          'kalıcı olarak silinecek. Devam etmek istediğine emin misin?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hesabı Sil',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await authService.deleteAccount();
      // Mesajlaşma/arama sinyal bağlantıları artık uygulama boyunca kalıcı
      // (bkz. messaging_service.dart, call_service.dart) - hesap silinirken
      // de gerçekten kapatmamız gerekiyor, bkz. profile_screen.dart _logout().
      MessagingService().disconnectSocket();
      CallService().disconnectSocket();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Beklenmeyen bir hata oluştu, tekrar dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Ayarlar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: _loadingPrefs
            ? Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
                // bkz. profile_screen.dart'taki aynı düzeltme - extendBodyBehindAppBar:
                // true, gövdeyi şeffaf ama hâlâ dokunuş yakalayan AppBar'ın
                // ARKASINA/ALTINA kadar uzatıyor; en üstteki içerik (başlık +
                // ilk satır) hem görsel olarak AppBar'ın "Ayarlar" yazısıyla
                // üst üste biniyor HEM DE o satırdaki dokunuşlar (ör. "Kiminle
                // eşleşmek istersin?" açılır menüsü) AppBar tarafından sessizce
                // yutuluyordu.
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  16,
                  16,
                ),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: AppScreenIntro(
                      icon: Icons.tune_rounded,
                      title: 'Kontrol sende',
                      subtitle:
                          'Eşleşme, güvenlik ve görünüm tercihlerini buradan yönet.',
                    ),
                  ),
                  _sectionTitle('Eşleşme Tercihleri'),
                  _dropdownTile(
                    title: 'Kiminle eşleşmek istersin?',
                    value: _genderFilter,
                    optionLabels: _genderLabels,
                    onChanged: _setGenderFilter,
                  ),
                  _switchTile(
                    title: 'Sadece onaylı hesaplar',
                    subtitle: 'En az 7 günlük, hesaplı kullanıcılarla eşleş',
                    value: _onlyVerified,
                    onChanged: _setOnlyVerified,
                  ),
                  _switchTile(
                    title: 'Ortak ilgi alanı şart olsun',
                    subtitle: 'Yalnızca profilinde en az bir ortak ilgi alanı '
                        'etiketi olan kişilerle eşleş',
                    value: _requireCommonInterest,
                    onChanged: _setRequireCommonInterest,
                  ),
                  _switchTile(
                    title: 'Yaş aralığı filtresi',
                    subtitle: _ageRangeEnabled
                        ? '${_ageRange.start.round()} - ${_ageRange.end.round()} yaş arası'
                        : 'Kapalı - her yaştan biriyle eşleş',
                    value: _ageRangeEnabled,
                    onChanged: _setAgeRangeEnabled,
                  ),
                  if (_ageRangeEnabled)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          RangeSlider(
                            values: _ageRange,
                            min: 13,
                            max: 90,
                            divisions: 77,
                            activeColor: AppColors.primary,
                            inactiveColor:
                                AppColors.textPrimary.withValues(alpha: 0.15),
                            labels: RangeLabels(
                              _ageRange.start.round().toString(),
                              _ageRange.end.round().toString(),
                            ),
                            onChanged: (values) =>
                                setState(() => _ageRange = values),
                            onChangeEnd: _setAgeRange,
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _countryFilterController,
                      style: TextStyle(color: AppColors.textPrimary),
                      onChanged: _setCountryFilter,
                      decoration: InputDecoration(
                        labelText: 'Ülke filtresi (boş = herkes)',
                        hintText: 'ör. Türkiye',
                        labelStyle: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  _switchTile(
                    title: 'Yakınlık bazlı eşleştirme',
                    subtitle: _proximityEnabled
                        ? '${_maxDistanceKm.round()} km içindekilerle eşleş (konumun paylaşılır)'
                        : 'Kapalı - mesafeye bakılmaksızın eşleş',
                    value: _proximityEnabled,
                    onChanged: _setProximityEnabled,
                  ),
                  if (_proximityEnabled)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14)),
                      child: Slider(
                        value: _maxDistanceKm,
                        min: 5,
                        max: 500,
                        divisions: 99,
                        activeColor: AppColors.primary,
                        inactiveColor:
                            AppColors.textPrimary.withValues(alpha: 0.15),
                        label: '${_maxDistanceKm.round()} km',
                        onChanged: (v) => setState(() => _maxDistanceKm = v),
                        onChangeEnd: _setMaxDistanceKm,
                      ),
                    ),
                  _switchTile(
                    title: 'Sadece metin modu',
                    subtitle:
                        'Kamera/mikrofon hiç açılmaz, yalnızca yazışırsın',
                    value: _textOnlyMode,
                    onChanged: _setTextOnlyMode,
                  ),
                  _switchTile(
                    title: 'Süreli hızlı eşleştirme',
                    subtitle:
                        '2 dakikalık kısa turlar, süre dolunca devam et/sıradaki seç',
                    value: _speedRoundMode,
                    onChanged: _setSpeedRoundMode,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Gizlilik'),
                  _switchTile(
                    title: 'Çevrimiçi durumumu gizle',
                    subtitle: 'Arkadaşların çevrimiçi olduğunu göremez',
                    value: _hideOnlineStatus,
                    onChanged: AuthService().isLoggedIn && !_savingPrivacy
                        ? _setHideOnlineStatus
                        : null,
                  ),
                  _switchTile(
                    title: 'Son görülmeyi gizle',
                    subtitle:
                        'Arkadaşların son ne zaman çevrimiçi olduğunu göremez',
                    value: _hideLastSeen,
                    onChanged: AuthService().isLoggedIn && !_savingPrivacy
                        ? _setHideLastSeen
                        : null,
                  ),
                  _switchTile(
                    title: 'Okundu bilgisi gönder',
                    subtitle:
                        'Kapatırsan mesajlarını okuduğun karşı tarafa gösterilmez',
                    value: _readReceiptsEnabled,
                    onChanged: AuthService().isLoggedIn && !_savingPrivacy
                        ? _setReadReceiptsEnabled
                        : null,
                  ),
                  _switchTile(
                    title: 'Keşfet\'te gizli mod',
                    subtitle:
                        'Açarsan başkalarının Keşfet akışında hiç görünmezsin '
                        '(sen yine de başkalarını görüp beğenebilirsin)',
                    value: _discoverInvisible,
                    onChanged: AuthService().isLoggedIn && !_savingPrivacy
                        ? _setDiscoverInvisible
                        : null,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Güvenlik'),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: AuthService().isLoggedIn
                        ? () => Navigator.of(context).push(AppPageRoute(
                            builder: (_) => const TrustedContactsScreen()))
                        : null,
                    child: GlassCard(
                      child: Row(
                        children: [
                          Icon(Icons.emergency_share_rounded,
                              color: AppColors.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Güvenilir kişiler ve panik butonu',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14)),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Görünüm'),
                  GlassCard(
                    child: Row(
                      children: [
                        Icon(Icons.text_fields_rounded,
                            color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Yazı boyutu',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14)),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: textScaleNotifier,
                          builder: (context, scale, _) =>
                              DropdownButton<double>(
                            value: scale,
                            dropdownColor: AppColors.surfaceElevated,
                            underline: const SizedBox.shrink(),
                            items: [
                              DropdownMenuItem(
                                  value: 0.85,
                                  child: Text('Küçük',
                                      style: TextStyle(
                                          color: AppColors.textPrimary))),
                              DropdownMenuItem(
                                  value: 1.0,
                                  child: Text('Normal',
                                      style: TextStyle(
                                          color: AppColors.textPrimary))),
                              DropdownMenuItem(
                                  value: 1.2,
                                  child: Text('Büyük',
                                      style: TextStyle(
                                          color: AppColors.textPrimary))),
                              DropdownMenuItem(
                                  value: 1.4,
                                  child: Text('Çok Büyük',
                                      style: TextStyle(
                                          color: AppColors.textPrimary))),
                            ],
                            onChanged: (value) {
                              if (value != null) setTextScalePreference(value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Tema seçimi - artık runtime'da değiştirilebiliyor (bkz.
                  // app_theme.dart'taki appThemeNotifier notu). Üç seçenek:
                  // mevcut koyu kimlik + iki yeni açık tema önerisi.
                  GlassCard(
                    child: Row(
                      children: [
                        Icon(Icons.palette_outlined,
                            color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Tema',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14)),
                        ),
                        ValueListenableBuilder<AppThemeVariant>(
                          valueListenable: appThemeNotifier,
                          builder: (context, variant, _) =>
                              DropdownButton<AppThemeVariant>(
                            value: variant,
                            dropdownColor: AppColors.surfaceElevated,
                            underline: const SizedBox.shrink(),
                            items: [
                              DropdownMenuItem(
                                value: AppThemeVariant.dark,
                                child: Text('Koyu (mevcut)',
                                    style: TextStyle(
                                        color: AppColors.textPrimary)),
                              ),
                              DropdownMenuItem(
                                value: AppThemeVariant.playful,
                                child: Text('Oyunlaştırılmış Enerji',
                                    style: TextStyle(
                                        color: AppColors.textPrimary)),
                              ),
                              DropdownMenuItem(
                                value: AppThemeVariant.trust,
                                child: Text('Güven & Berraklık',
                                    style: TextStyle(
                                        color: AppColors.textPrimary)),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) setAppThemePreference(value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Bildirimler'),
                  _switchTile(
                    title: 'Anlık bildirimler',
                    subtitle: 'Yeni mesaj ve eşleşme bildirimleri al',
                    value: _notifications,
                    onChanged: _setNotifications,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Hakkında'),
                  _navTile(
                    icon: Icons.description_outlined,
                    title: 'Topluluk Kuralları',
                    onTap: () => _openUrl(communityRulesUrl),
                  ),
                  _navTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Gizlilik Politikası',
                    onTap: () => _openUrl(privacyPolicyUrl),
                  ),
                  _navTile(
                      icon: Icons.info_outline,
                      title: 'Uygulama Hakkında',
                      subtitle:
                          _appVersion.isEmpty ? null : 'Sürüm $_appVersion'),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed:
                          _deletingAccount ? null : _handleDeleteAccountTap,
                      child: _deletingAccount
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.danger),
                            )
                          : Text('Hesabı Sil',
                              style: TextStyle(color: AppColors.danger)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          title,
          style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _comingSoonBadge() => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Yakında',
          style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool comingSoon = false,
  }) {
    final disabled = onChanged == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.primary,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
              if (comingSoon) _comingSoonBadge(),
            ],
          ),
          subtitle: Text(subtitle,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _dropdownTile({
    required String title,
    required String value,
    required Map<String, String> optionLabels,
    required ValueChanged<String?>? onChanged,
    bool comingSoon = false,
  }) {
    final disabled = onChanged == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14)),
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                if (comingSoon) _comingSoonBadge(),
              ],
            ),
            DropdownButton<String>(
              value: value,
              dropdownColor: AppColors.surfaceElevated,
              underline: const SizedBox(),
              style: TextStyle(color: AppColors.primaryLight),
              items: optionLabels.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(title,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(color: AppColors.textFaint, fontSize: 12))
            : null,
        trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
        onTap: onTap ?? () {},
      ),
    );
  }

  /// Bir URL'yi cihazın varsayılan tarayıcısında açar. Sayfa henüz
  /// yayınlanmadıysa ya da cihazda hiçbir tarayıcı bulunamazsa (çok nadir)
  /// kullanıcıya sessizce hiçbir şey olmamış gibi görünmesin diye bir
  /// snackbar ile bilgilendiriyoruz.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sayfa açılamadı, tekrar dene.')),
      );
    }
  }
}
