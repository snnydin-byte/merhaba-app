import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/match_preferences_repository.dart';
import '../services/notification_preferences_repository.dart';
import '../services/push_notification_service.dart';
import '../services/session_navigation_coordinator.dart';
import '../theme/app_theme.dart';
import '../utils/text_scale_notifier.dart';
import '../widgets/session_end_progress_dialog.dart';
import 'trusted_contacts_screen.dart';
import 'feedback_diagnostics_screen.dart';
import '../utils/session_transient_ui.dart';

// GitHub Pages üzerinde barındırılan statik sayfalar (bkz. proje kökündeki
// docs/ klasörü). Play Store yayını öncesi GERÇEK içerikle
// (docs/privacy.html, docs/community-rules.html, docs/terms.html)
// Pages'te yayınlanmış olmaları gerekiyor - bkz. KURULUM.md "Play Store
// Yayın Hazırlığı" bölümü.
const String privacyPolicyUrl =
    'https://snnydin-byte.github.io/merhaba-app/privacy.html';
const String communityRulesUrl =
    'https://snnydin-byte.github.io/merhaba-app/community-rules.html';
const String termsUrl = 'https://snnydin-byte.github.io/merhaba-app/terms.html';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final MatchPreferencesRepository _matchPreferences =
      MatchPreferencesRepository();
  final NotificationPreferencesRepository _notificationPreferences =
      NotificationPreferencesRepository();

  bool _notifications = true;
  bool _savingNotifications = false;
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
  bool _advancedMatchFiltersOpen = false;

  // Eşleşme (Dating) katmanı - Batch E. discoverInvisible SUNUCUDA hesaba
  // bağlı (SharedPreferences DEĞİL - hideOnlineStatus/hideLastSeen ile AYNI
  // desen), o yüzden _loadPrefs()'te değil kullanıcı yüklenince ayarlanıyor.
  bool _discoverInvisible = false;

  // Gizlilik ayarları (#39/#24 anket maddeleri) - SharedPreferences DEĞİL,
  // sunucuda hesaba bağlı olarak saklanır (bkz. AuthService.updateProfile).
  // Oturum yokken hesap ayarları devre dışıdır.
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
    AuthService().sessionState.addListener(_syncPrivacyFromSession);
    _loadPrefs();
    _loadAppVersion();
  }

  @override
  void dispose() {
    AuthService().sessionState.removeListener(_syncPrivacyFromSession);
    _countryFilterController.dispose();
    super.dispose();
  }

  AppUser? get _sessionUser => AuthService().sessionState.value.user;

  bool get _isLoggedIn => AuthService().sessionState.value.isAuthenticated;

  void _syncPrivacyFromSession() {
    if (!mounted) return;
    final user = _sessionUser;
    final nextHideOnline = user?.hideOnlineStatus ?? false;
    final nextHideLastSeen = user?.hideLastSeen ?? false;
    final nextReadReceipts = user?.readReceiptsEnabled ?? true;
    final nextDiscoverInvisible = user?.discoverInvisible ?? false;
    final changed = _hideOnlineStatus != nextHideOnline ||
        _hideLastSeen != nextHideLastSeen ||
        _readReceiptsEnabled != nextReadReceipts ||
        _discoverInvisible != nextDiscoverInvisible;
    if (!changed && user != null) return;
    setState(() {
      _hideOnlineStatus = nextHideOnline;
      _hideLastSeen = nextHideLastSeen;
      _readReceiptsEnabled = nextReadReceipts;
      _discoverInvisible = nextDiscoverInvisible;
    });
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
    final results = await Future.wait<Object>([
      _notificationPreferences.loadEnabled(),
      _matchPreferences.load(),
    ]);
    final notificationsEnabled = results[0] as bool;
    final match = results[1] as MatchPreferences;
    if (!mounted) return;
    setState(() {
      _notifications = notificationsEnabled;
      _genderFilter = match.genderFilter;
      _ageRangeEnabled = match.ageRangeEnabled;
      _ageRange = RangeValues(
        (match.minAge ?? 18).toDouble(),
        (match.maxAge ?? 60).toDouble(),
      );
      _onlyVerified = match.onlyVerified;
      _countryFilterController.text = match.countryFilter;
      _proximityEnabled = match.proximityEnabled;
      _maxDistanceKm = (match.maxDistanceKm ?? 100).toDouble();
      _textOnlyMode = match.textOnly;
      _speedRoundMode = match.speedRound;
      _requireCommonInterest = match.requireCommonInterest;
      final user = _sessionUser;
      if (user != null) {
        _hideOnlineStatus = user.hideOnlineStatus;
        _hideLastSeen = user.hideLastSeen;
        _readReceiptsEnabled = user.readReceiptsEnabled;
        _discoverInvisible = user.discoverInvisible;
      }
      _loadingPrefs = false;
    });
  }

  Future<void> _setHideOnlineStatus(bool value) => _savePrivacyField(
        optimisticUpdate: () => _hideOnlineStatus = value,
        rollback: () => _hideOnlineStatus = !value,
        hideOnlineStatus: value,
      );

  Future<void> _setHideLastSeen(bool value) => _savePrivacyField(
        optimisticUpdate: () => _hideLastSeen = value,
        rollback: () => _hideLastSeen = !value,
        hideLastSeen: value,
      );

  Future<void> _setReadReceiptsEnabled(bool value) => _savePrivacyField(
        optimisticUpdate: () => _readReceiptsEnabled = value,
        rollback: () => _readReceiptsEnabled = !value,
        readReceiptsEnabled: value,
      );

  Future<void> _setDiscoverInvisible(bool value) => _savePrivacyField(
        optimisticUpdate: () => _discoverInvisible = value,
        rollback: () => _discoverInvisible = !value,
        discoverInvisible: value,
      );

  Future<void> _savePrivacyField({
    required VoidCallback optimisticUpdate,
    required VoidCallback rollback,
    bool? hideOnlineStatus,
    bool? hideLastSeen,
    bool? readReceiptsEnabled,
    bool? discoverInvisible,
  }) async {
    if (_savingPrivacy || !_isLoggedIn) return;

    setState(() {
      optimisticUpdate();
      _savingPrivacy = true;
    });

    try {
      await AuthService().updateProfile(
        hideOnlineStatus: hideOnlineStatus,
        hideLastSeen: hideLastSeen,
        readReceiptsEnabled: readReceiptsEnabled,
        discoverInvisible: discoverInvisible,
      );
    } catch (_) {
      if (!mounted) return;
      setState(rollback);
      showSessionSnackBar(
        context,
        const SnackBar(
            content: Text('Ayar kaydedilemedi; değişiklik geri alındı.')),
        priority: SessionFeedbackPriority.high,
      );
    } finally {
      if (mounted) setState(() => _savingPrivacy = false);
    }
  }

  Future<void> _setNotifications(bool value) async {
    if (_savingNotifications || value == _notifications) return;
    final previous = _notifications;
    setState(() {
      _notifications = value;
      _savingNotifications = true;
    });
    try {
      await PushNotificationService().setEnabled(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _notifications = previous);
      showSessionSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Bildirim tercihi kaydedilemedi; değişiklik geri alındı.',
          ),
        ),
        priority: SessionFeedbackPriority.high,
      );
    } finally {
      if (mounted) setState(() => _savingNotifications = false);
    }
  }

  Future<void> _setGenderFilter(String? value) async {
    if (value == null || value == _genderFilter) return;
    final previous = _genderFilter;
    setState(() => _genderFilter = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setGenderFilter(value),
      rollback: () => _genderFilter = previous,
    );
  }

  Future<void> _setOnlyVerified(bool value) async {
    final previous = _onlyVerified;
    setState(() => _onlyVerified = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setOnlyVerified(value),
      rollback: () => _onlyVerified = previous,
    );
  }

  Future<void> _setAgeRangeEnabled(bool value) async {
    final previous = _ageRangeEnabled;
    setState(() => _ageRangeEnabled = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setAgeRange(
        enabled: value,
        min: _ageRange.start.round(),
        max: _ageRange.end.round(),
      ),
      rollback: () => _ageRangeEnabled = previous,
    );
  }

  Future<void> _setAgeRange(RangeValues values) async {
    final previous = _ageRange;
    setState(() => _ageRange = values);
    if (!_ageRangeEnabled) return;
    await _saveMatchPreference(
      save: () => _matchPreferences.setAgeRange(
        enabled: true,
        min: values.start.round(),
        max: values.end.round(),
      ),
      rollback: () => _ageRange = previous,
    );
  }

  Future<void> _setCountryFilter(String value) async {
    try {
      await _matchPreferences.setCountryFilter(value);
    } catch (_) {
      if (!mounted) return;
      final persisted = await _matchPreferences.load();
      if (!mounted) return;
      _countryFilterController.text = persisted.countryFilter;
      _showMatchPreferenceSaveError();
    }
  }

  Future<void> _setProximityEnabled(bool value) async {
    final previous = _proximityEnabled;
    setState(() => _proximityEnabled = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setProximity(
        enabled: value,
        maxDistanceKm: _maxDistanceKm.round(),
      ),
      rollback: () => _proximityEnabled = previous,
    );
  }

  Future<void> _setMaxDistanceKm(double value) async {
    final previous = _maxDistanceKm;
    setState(() => _maxDistanceKm = value);
    if (!_proximityEnabled) return;
    await _saveMatchPreference(
      save: () => _matchPreferences.setProximity(
        enabled: true,
        maxDistanceKm: value.round(),
      ),
      rollback: () => _maxDistanceKm = previous,
    );
  }

  Future<void> _setTextOnlyMode(bool value) async {
    final previous = _textOnlyMode;
    setState(() => _textOnlyMode = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setTextOnly(value),
      rollback: () => _textOnlyMode = previous,
    );
  }

  Future<void> _setSpeedRoundMode(bool value) async {
    final previous = _speedRoundMode;
    setState(() => _speedRoundMode = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setSpeedRound(value),
      rollback: () => _speedRoundMode = previous,
    );
  }

  Future<void> _setRequireCommonInterest(bool value) async {
    final previous = _requireCommonInterest;
    setState(() => _requireCommonInterest = value);
    await _saveMatchPreference(
      save: () => _matchPreferences.setRequireCommonInterest(value),
      rollback: () => _requireCommonInterest = previous,
    );
  }

  Future<void> _saveMatchPreference({
    required Future<void> Function() save,
    required VoidCallback rollback,
  }) async {
    try {
      await save();
    } catch (_) {
      if (!mounted) return;
      setState(rollback);
      _showMatchPreferenceSaveError();
    }
  }

  void _showMatchPreferenceSaveError() {
    showSessionSnackBar(
      context,
      const SnackBar(
        content: Text('Eşleşme tercihi kaydedilemedi; değişiklik geri alındı.'),
      ),
      priority: SessionFeedbackPriority.high,
    );
  }

  Future<void> _handleDeleteAccountTap() async {
    final authService = AuthService();

    if (!authService.isLoggedIn) {
      showSessionDialog<void>(
        deduplicationKey: 'settings_screen.dialog.1',
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Silinecek hesap yok',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            'Hesap işlemleri için yeniden giriş yapman gerekiyor.',
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

    final confirmed = await showSessionDialog<bool>(
      deduplicationKey: 'settings_screen.dialog.2',
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
    showSessionEndProgressDialog(context);
    try {
      await authService.deleteAccount();
      if (!mounted) return;
      closeSessionEndProgressDialog(context);
      await SessionNavigationCoordinator().resetToLogin();
    } on AuthException catch (e) {
      if (mounted) {
        closeSessionEndProgressDialog(context);
        showSessionSnackBar(
          context,
          SnackBar(content: Text(e.message)),
          priority: SessionFeedbackPriority.normal,
        );
      }
    } catch (_) {
      if (mounted) {
        closeSessionEndProgressDialog(context);
        showSessionSnackBar(
          context,
          const SnackBar(
              content: Text('Beklenmeyen bir hata oluştu, tekrar dene.')),
          priority: SessionFeedbackPriority.high,
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
                      title: 'Eşleşmeni ayarla',
                      subtitle:
                          'Kimlerle tanışacağını, görünürlüğünü ve güvenliğini yönet.',
                    ),
                  ),
                  _matchSummaryCard(),
                  const SizedBox(height: AppSpacing.lg),
                  _sectionTitle('Temel eşleşme tercihleri'),
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
                  _advancedFiltersTile(),
                  if (_advancedMatchFiltersOpen) ...[
                    _switchTile(
                      title: 'Yaş aralığı filtresi',
                      subtitle: _ageRangeEnabled
                          ? '${_ageRange.start.round()} - ${_ageRange.end.round()} yaş arası'
                          : 'Kapalı - her yaştan biriyle eşleş',
                      value: _ageRangeEnabled,
                      onChanged: _setAgeRangeEnabled,
                    ),
                    if (_ageRangeEnabled)
                      _sliderSurface(
                        child: RangeSlider(
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
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _countryFilterController,
                        style: TextStyle(color: AppColors.textPrimary),
                        onChanged: _setCountryFilter,
                        decoration: const InputDecoration(
                          labelText: 'Ülke filtresi',
                          hintText: 'Örn. Türkiye',
                        ),
                      ),
                    ),
                    _switchTile(
                      title: 'Yakınlık bazlı eşleştirme',
                      subtitle: _proximityEnabled
                          ? '${_maxDistanceKm.round()} km içindekilerle eşleş'
                          : 'Kapalı - konumun paylaşılmaz',
                      value: _proximityEnabled,
                      onChanged: _setProximityEnabled,
                    ),
                    if (_proximityEnabled)
                      _sliderSurface(
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
                  ],
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
                  _sectionTitle('Görünürlük ve mesajlar'),
                  _switchTile(
                    title: 'Çevrimiçi durumumu gizle',
                    subtitle: 'Arkadaşların çevrimiçi olduğunu göremez',
                    value: _hideOnlineStatus,
                    onChanged: _isLoggedIn && !_savingPrivacy
                        ? _setHideOnlineStatus
                        : null,
                  ),
                  _switchTile(
                    title: 'Son görülmeyi gizle',
                    subtitle:
                        'Arkadaşların son ne zaman çevrimiçi olduğunu göremez',
                    value: _hideLastSeen,
                    onChanged: _isLoggedIn && !_savingPrivacy
                        ? _setHideLastSeen
                        : null,
                  ),
                  _switchTile(
                    title: 'Okundu bilgisi gönder',
                    subtitle:
                        'Kapatırsan mesajlarını okuduğun karşı tarafa gösterilmez',
                    value: _readReceiptsEnabled,
                    onChanged: _isLoggedIn && !_savingPrivacy
                        ? _setReadReceiptsEnabled
                        : null,
                  ),
                  _switchTile(
                    title: 'Keşfet\'te gizli mod',
                    subtitle:
                        'Açarsan başkalarının Keşfet akışında hiç görünmezsin '
                        '(sen yine de başkalarını görüp beğenebilirsin)',
                    value: _discoverInvisible,
                    onChanged: _isLoggedIn && !_savingPrivacy
                        ? _setDiscoverInvisible
                        : null,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Güvenlik ve destek'),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: _isLoggedIn
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
                  _sectionTitle('Deneyim'),
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
                    onChanged: _savingNotifications ? null : _setNotifications,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('Uygulama ve hesap'),
                  _navTile(
                    icon: Icons.gavel_outlined,
                    title: 'Kullanım Koşulları',
                    onTap: () => _openUrl(termsUrl),
                  ),
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
                  if (kDebugMode)
                    _navTile(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Feedback Tanılama',
                      subtitle: 'Aksiyon hata ve timeout sayaçları',
                      onTap: () => Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) => const FeedbackDiagnosticsScreen(),
                        ),
                      ),
                    ),
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

  Widget _matchSummaryCard() {
    final activeFilters = [
      _genderFilter != 'herkes',
      _onlyVerified,
      _requireCommonInterest,
      _ageRangeEnabled,
      _countryFilterController.text.trim().isNotEmpty,
      _proximityEnabled,
      _textOnlyMode,
      _speedRoundMode,
    ].where((value) => value).length;

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child:
                Icon(Icons.travel_explore_rounded, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeFilters == 0
                      ? 'Dünyaya açıksın'
                      : '$activeFilters tercih etkin',
                  style: AppText.subheading.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  activeFilters == 0
                      ? 'Yeni insanlarla rastgele tanışmaya hazırsın.'
                      : 'Bu tercihler yeni eşleşmelerini yönlendirir.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedFiltersTile() {
    final active = _ageRangeEnabled ||
        _countryFilterController.text.trim().isNotEmpty ||
        _proximityEnabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(
          () => _advancedMatchFiltersOpen = !_advancedMatchFiltersOpen,
        ),
        child: GlassCard(
          child: Row(
            children: [
              Icon(Icons.tune_rounded,
                  color: active ? AppColors.secondary : AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gelişmiş filtreler',
                        style: AppText.subheading.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? 'Yaş, ülke veya yakınlık tercihlerin açık.'
                          : 'Yaş, ülke ve yakınlık tercihlerini özelleştir.',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              Icon(
                _advancedMatchFiltersOpen
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderSurface({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: child,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primary,
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(title,
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                if (comingSoon) _comingSoonBadge(),
              ],
            ),
            subtitle: Text(subtitle,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            value: value,
            onChanged: onChanged,
          ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 15)),
                  if (comingSoon) _comingSoonBadge(),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: value,
                isExpanded: true,
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
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Icon(icon, color: AppColors.textSecondary),
          title: Text(title,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          subtitle: subtitle != null
              ? Text(subtitle,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12))
              : null,
          trailing:
              Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
          onTap: onTap ?? () {},
        ),
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
      showSessionSnackBar(
        context,
        const SnackBar(content: Text('Sayfa açılamadı, tekrar dene.')),
        priority: SessionFeedbackPriority.high,
      );
    }
  }
}
