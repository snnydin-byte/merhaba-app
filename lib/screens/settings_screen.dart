import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/messaging_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

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
      _loadingPrefs = false;
    });
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

  Future<void> _handleDeleteAccountTap() async {
    final authService = AuthService();

    if (!authService.isLoggedIn) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Silinecek hesap yok',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Şu an misafir olarak geziniyorsun, silinecek bir hesabın yok.',
            style: TextStyle(color: Colors.white70),
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
        title: const Text('Hesabı sil', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Bu işlem geri alınamaz. Hesabın ve profil bilgilerin sunucudan '
          'kalıcı olarak silinecek. Devam etmek istediğine emin misin?',
          style: TextStyle(color: Colors.white70),
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
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      children: [
                        RangeSlider(
                          values: _ageRange,
                          min: 13,
                          max: 90,
                          divisions: 77,
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.white.withValues(alpha: 0.15),
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
                    subtitle: _appVersion.isEmpty
                        ? null
                        : 'Sürüm $_appVersion'),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed:
                        _deletingAccount ? null : _handleDeleteAccountTap,
                    child: _deletingAccount
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.danger),
                          )
                        : const Text('Hesabı Sil',
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
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _comingSoonBadge() => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Yakında',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
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
          color: Colors.white.withValues(alpha: 0.05),
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
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              if (comingSoon) _comingSoonBadge(),
            ],
          ),
          subtitle: Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
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
          color: Colors.white.withValues(alpha: 0.05),
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
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                if (comingSoon) _comingSoonBadge(),
              ],
            ),
            DropdownButton<String>(
              value: value,
              dropdownColor: AppColors.surfaceElevated,
              underline: const SizedBox(),
              style: const TextStyle(color: AppColors.primaryLight),
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
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 12))
            : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
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
