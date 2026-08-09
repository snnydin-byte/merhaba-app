import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/adult_age_policy.dart';
import '../services/auth_service.dart';
import '../services/session_navigation_coordinator.dart';
import '../widgets/auth_session_builder.dart';
import '../widgets/session_end_progress_dialog.dart';
import '../theme/app_theme.dart';
import 'achievements_screen.dart';
import 'leaderboard_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import '../utils/session_transient_ui.dart';

/// Giriş yapmış kullanıcı için profil bilgileri (isim, biyografi, cinsiyet,
/// yaş, ilgi alanları, ülke/dil - hepsi düzenlenebilir; e-posta salt-okunur)
/// ve çıkış yap; oturum yoksa giriş/kayda yönlendirir.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _countryController = TextEditingController();
  final _languageController = TextEditingController();
  final _interestController = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  String? _error;
  String? _gender; // 'erkek' | 'kadın' | null
  List<String> _interests = [];
  // Batch C - burç/doğum tarihi (yalnızca kendi profilinde dolu gelir).
  DateTime? _birthDate;
  // Eşleşme (Dating) katmanı - Batch E. Profil rozetleri, en fazla 3.
  List<String> _selectedBadges = [];

  bool _uploadingPhoto = false;
  bool _uploadingVideo = false;
  bool _uploadingSelfie = false;

  // discoverStore.js PROFILE_BADGE_CATALOG ile BİREBİR aynı id'ler - sunucu
  // bunun dışındaki bir değeri reddediyor (bkz. isValidProfileBadges).
  static const Map<String, String> _badgeCatalog = {
    'kahve-tutkunu': 'Kahve tutkunu',
    'erken-kalkan': 'Erken kalkan',
    'gece-kusu': 'Gece kuşu',
    'sporcu': 'Sporcu',
    'kitap-kurdu': 'Kitap kurdu',
    'gezgin': 'Gezgin',
    'evcil-hayvan-sever': 'Evcil hayvan sever',
    'yemek-tutkunu': 'Yemek tutkunu',
    'muzisyen': 'Müzisyen',
    'sanatci': 'Sanatçı',
    'oyuncu': 'Oyuncu',
    'doga-sever': 'Doğa sever',
  };

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _countryController.dispose();
    _languageController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  void _loadFieldsFromUser(AppUser user) {
    _nameController.text = user.displayName;
    _bioController.text = user.bio;
    _countryController.text = user.country ?? '';
    _languageController.text = user.language ?? '';
    _gender = user.gender;
    _interests = List.of(user.interests);
    _birthDate =
        user.birthDate != null ? DateTime.tryParse(user.birthDate!) : null;
    _selectedBadges = List.of(user.profileBadges);
  }

  void _startEditing(AppUser user) {
    _loadFieldsFromUser(user);
    setState(() => _editing = true);
  }

  void _addInterest() {
    final tag = _interestController.text.trim().toLowerCase();
    if (tag.isEmpty || _interests.contains(tag) || _interests.length >= 10) {
      _interestController.clear();
      return;
    }
    setState(() {
      _interests.add(tag);
      _interestController.clear();
    });
  }

  /// Avatara dokunulunca açılan seçenek listesi. Foto zaten varsa "Kaldır"
  /// seçeneği de gösterilir. Galeriden seçim yeterli - kamerayla çekme
  /// PreCallScreen'de zaten kullanılan permission_handler akışıyla
  /// karışmasın diye şimdilik eklenmedi, istenirse ayrı bir görev olur.
  Future<void> _showPhotoOptions(AppUser user) async {
    if (_uploadingPhoto) return;
    final choice = await showSessionModalBottomSheet<String>(
      deduplicationKey: 'profile_screen.sheet.1',
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppColors.textSecondary),
              title: Text('Galeriden Seç',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            ListTile(
              leading: Icon(Icons.emoji_emotions_outlined,
                  color: AppColors.textSecondary),
              title: Text('Emoji Avatarı Kullan',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(sheetContext).pop('avatar'),
            ),
            if (user.avatarConfig != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text('Emoji Avatarını Kaldır',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.of(sheetContext).pop('remove-avatar'),
              ),
            if (user.photoUrl != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text('Fotoğrafı Kaldır',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
          ],
        ),
      ),
    );

    if (choice == 'pick') {
      await _pickAndUploadPhoto();
    } else if (choice == 'remove') {
      await _removePhoto();
    } else if (choice == 'avatar') {
      await _showAvatarBuilderDialog();
    } else if (choice == 'remove-avatar') {
      try {
        await _authService.updateProfile(clearAvatarConfig: true);
        if (mounted) setState(() {});
      } on AuthException catch (e) {
        _showSnack(e.message);
      }
    }
  }

  static const List<String> _avatarColors = [
    '#7C4DFF',
    '#00BFA5',
    '#FF5470',
    '#FFB74D',
    '#2E7D32',
    '#1976D2',
  ];
  static const List<String> _avatarEmojis = [
    '😀',
    '😎',
    '🥳',
    '🤓',
    '😺',
    '🦊',
    '🐼',
    '🌟',
    '🔥',
    '🌈',
    '🎧',
    '🚀',
  ];

  /// Avatar oluşturucu (Batch G) - basit renk+emoji seçici, yeni bir
  /// illüstrasyon/ML paketi GEREKTİRMİYOR (bkz. server.js doğrulaması).
  Future<void> _showAvatarBuilderDialog() async {
    String selectedColor = _avatarColors.first;
    String selectedEmoji = _avatarEmojis.first;
    final result = await showSessionDialog<bool>(
      deduplicationKey: 'profile_screen.dialog.1',
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Emoji Avatarı',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: _parseHexColor(selectedColor),
                child:
                    Text(selectedEmoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: _avatarColors.map((hex) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = hex),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: _parseHexColor(hex),
                      child: selectedColor == hex
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: _avatarEmojis.map((emoji) {
                  final selected = selectedEmoji == emoji;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedEmoji = emoji),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Vazgeç')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    try {
      await _authService.updateProfile(
        avatarConfig:
            AvatarConfig(backgroundColor: selectedColor, emoji: selectedEmoji),
      );
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      _showSnack(e.message);
    }
  }

  Color _parseHexColor(String hex) {
    final value = int.parse(hex.replaceAll('#', ''), radix: 16);
    return Color(0xFF000000 | value);
  }

  // Profil GÖRÜNTÜLEME ekranında ayrı bir hata metni alanı yok (o sadece
  // düzenleme formunda var, bkz. _buildEditBody/_error) - foto işlemleri
  // view modundan tetiklendiği için hataları kısa bir SnackBar ile
  // gösteriyoruz.
  void _showSnack(String message) {
    if (!mounted) return;
    showSessionSnackBar(
      context,
      SnackBar(content: Text(message)),
      priority: SessionFeedbackPriority.normal,
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      // maxWidth/imageQuality ile sıkıştırma - profil fotoğrafı için 1024px
      // ve %85 kalite fazlasıyla yeterli, hem yükleme hem sunucu tarafındaki
      // Cloudinary kullanımını (bkz. photoStorage.js) makul tutuyor.
      picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      _showSnack('Fotoğraf seçilemedi, tekrar dene.');
      return;
    }
    if (picked == null) return; // kullanıcı seçim yapmadan vazgeçti

    setState(() => _uploadingPhoto = true);
    try {
      await _authService.uploadProfilePhoto(File(picked.path));
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Fotoğraf yüklenemedi, tekrar dene.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      await _authService.removeProfilePhoto();
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Fotoğraf kaldırılamadı, tekrar dene.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // Video profil tanıtımı (Batch C) - kayıt/oynatma için ayrı bir video
  // oynatıcı paketi eklemek yerine (bkz. proje kapsam notu) yüklenen video
  // url_launcher ile CİHAZIN kendi video oynatıcısında/tarayıcısında
  // açılıyor - fotoğraf yükleme akışıyla AYNI desen, yalnızca ImagePicker.
  // pickVideo() kullanıyor.
  Future<void> _pickAndUploadIntroVideo() async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
    } catch (_) {
      _showSnack('Video seçilemedi, tekrar dene.');
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingVideo = true);
    try {
      await _authService.uploadIntroVideo(File(picked.path));
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Video yüklenemedi, tekrar dene.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  /// Selfie doğrulama rozeti (Batch E) - kameradan çekilir (galeriden değil,
  /// eski bir fotoğrafın "gerçek zamanlı" olmadığı bariz olmasın diye en
  /// azından kamerayı zorunlu kılıyoruz - tam bir canlılık/liveness kontrolü
  /// DEĞİL, ama basit bir caydırıcı). Onay AI DEĞİL, Sinan'ın manuel admin
  /// incelemesiyle olur (bkz. server.js).
  Future<void> _pickAndUploadSelfie() async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    } catch (_) {
      _showSnack('Fotoğraf çekilemedi, tekrar dene.');
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingSelfie = true);
    try {
      await _authService.uploadSelfieVerification(File(picked.path));
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Fotoğraf yüklenemedi, tekrar dene.');
    } finally {
      if (mounted) setState(() => _uploadingSelfie = false);
    }
  }

  Future<void> _removeIntroVideo() async {
    setState(() => _uploadingVideo = true);
    try {
      await _authService.removeIntroVideo();
      if (mounted) setState(() {});
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Video kaldırılamadı, tekrar dene.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _playIntroVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('Video açılamadı.');
    }
  }

  Future<void> _saveProfile() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      setState(() => _error = 'İsim boş olamaz.');
      return;
    }

    final birthDate = _birthDate;
    if (birthDate == null || !AdultAgePolicy.isAdult(birthDate)) {
      setState(() =>
          _error = 'Doğum tarihi zorunludur ve 18 yaşını doldurmuş olmalısın.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _authService.updateProfile(
        displayName: newName,
        bio: _bioController.text.trim(),
        gender: _gender,
        interests: _interests,
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        language: _languageController.text.trim().isEmpty
            ? null
            : _languageController.text.trim(),
        birthDate: AdultAgePolicy.toApiDate(birthDate),
        profileBadges: _selectedBadges,
      );
      if (mounted) setState(() => _editing = false);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Beklenmeyen bir hata oluştu, tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    showSessionEndProgressDialog(context);
    try {
      await _authService.logout();
      if (!mounted) return;
      closeSessionEndProgressDialog(context);
      await SessionNavigationCoordinator().resetToLogin();
    } catch (_) {
      if (!mounted) return;
      closeSessionEndProgressDialog(context);
      showSessionSnackBar(
        context,
        const SnackBar(content: Text('Çıkış tamamlanamadı, tekrar dene.')),
        priority: SessionFeedbackPriority.normal,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthSessionBuilder(
      builder: (context, _, user) => Scaffold(
        extendBodyBehindAppBar: !_editing,
        appBar: AppBar(
          title: Text(_editing ? 'Profilini düzenle' : 'Profil'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (user != null && !_editing)
              IconButton(
                onPressed: () => _startEditing(user),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Profili Düzenle',
              ),
          ],
        ),
        body: AppBackground(
          child: user == null
              ? _buildGuestBody()
              : (_editing ? _buildEditBody() : _buildProfileBody(user)),
        ),
      ),
    );
  }

  Widget _buildGuestBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, color: AppColors.textFaint, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Oturumun açık değil',
              style: AppText.subheading.copyWith(fontSize: 17),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Profilini görmek ve düzenlemek için giriş yap ya da bir hesap oluştur.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            GradientButton(
              height: 52,
              onPressed: () {
                Navigator.of(context)
                    .push(AppPageRoute(builder: (_) => const LoginScreen()));
              },
              child: const Text('Giriş Yap / Hesap Oluştur',
                  style: AppText.button),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarHeader(AppUser user) {
    final metadata = <Widget>[
      if (user.country?.isNotEmpty == true)
        PillBadge(
          label: user.country!,
          color: AppColors.textSecondary,
          icon: Icons.public_rounded,
        ),
      if (user.language?.isNotEmpty == true)
        PillBadge(
          label: user.language!,
          color: AppColors.textSecondary,
          icon: Icons.translate_rounded,
        ),
    ];

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showPhotoOptions(user),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Canva mockup'ındaki avatarı saran ince neon halka.
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.secondary, width: 2),
                    boxShadow: neonGlow(AppColors.secondary,
                        opacity: 0.4, blurRadius: 22, spreadRadius: 1),
                  ),
                  child: _buildAvatarCircle(user),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.displayName, style: AppText.subheading),
              if (user.verified) ...[
                const SizedBox(width: 6),
                Icon(Icons.verified_rounded,
                    color: AppColors.secondary, size: 18),
              ],
            ],
          ),
          if (metadata.isNotEmpty || user.loginStreak > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ...metadata,
                if (user.loginStreak > 1)
                  PillBadge(
                    label: '${user.loginStreak} günlük seri',
                    color: AppColors.primary,
                    icon: Icons.local_fire_department_rounded,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarCircle(AppUser user) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: user.photoUrl == null && user.avatarConfig != null
              ? _parseHexColor(user.avatarConfig!.backgroundColor)
              : AppColors.primary.withValues(alpha: 0.25),
          backgroundImage:
              user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
          child: user.photoUrl != null
              ? null
              // Avatar oluşturucu (Batch G) - fotoğraf yoksa, emoji
              // avatarı ayarlanmışsa isim baş harfi yerine ONU göster.
              : Text(
                  user.avatarConfig?.emoji ??
                      (user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : '?'),
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.bold),
                ),
        ),
        // Sağ-altta küçük bir kamera rozeti - foto değiştirilebilir
        // olduğunu gösteren tanıdık bir işaret (WhatsApp/Instagram
        // profil düzenleme deseniyle aynı).
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: _uploadingPhoto
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 14),
          ),
        ),
      ],
    );
  }

  Widget _profileCompletionCard(AppUser user) {
    final completedFields = [
      user.photoUrl != null || user.avatarConfig != null,
      user.bio.trim().isNotEmpty,
      user.country?.trim().isNotEmpty == true,
      user.language?.trim().isNotEmpty == true,
      user.interests.isNotEmpty,
    ].where((value) => value).length;
    final progress = completedFields / 5;

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress == 1
                      ? 'Profilin tanışmaya hazır'
                      : 'Profilini tamamla',
                  style: AppText.subheading.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  progress == 1
                      ? 'İnsanlar seni daha kolay tanıyabilir.'
                      : '$completedFields/5 bilgi eklendi',
                  style: AppText.caption,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor:
                        AppColors.textPrimary.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(AppColors.secondary),
                  ),
                ),
              ],
            ),
          ),
          if (progress < 1) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _startEditing(user),
              child: const Text('Tamamla'),
            ),
          ],
        ],
      ),
    );
  }

  /// Video/kısa klip profil tanıtımı (Batch C) - en fazla 30sn, galeriden
  /// seçilir, Cloudinary'ye yüklenir (bkz. auth_service.dart
  /// uploadIntroVideo). Oynatma cihazın kendi video oynatıcısında/
  /// tarayıcısında açılır (bkz. _playIntroVideo notu).
  Widget _introVideoCard(AppUser user) {
    if (_uploadingVideo) {
      return GlassCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (user.introVideoUrl == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: _pickAndUploadIntroVideo,
        child: GlassCard(
          child: Row(
            children: [
              Icon(Icons.videocam_outlined, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Video tanıtım ekle (en fazla 30sn)',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              ),
              Icon(Icons.add, color: AppColors.textFaint),
            ],
          ),
        ),
      );
    }
    return GlassCard(
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _playIntroVideo(user.introVideoUrl!),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.play_arrow_rounded, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Video tanıtımın',
                style: AppText.subheading.copyWith(fontSize: 14)),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
            onPressed: _removeIntroVideo,
          ),
        ],
      ),
    );
  }

  /// Selfie doğrulama rozeti kartı (Batch E) - durum makinesi: none ->
  /// (yükle) -> pending -> (Sinan admin panelinden onaylar/reddeder) ->
  /// approved/rejected. rejected'ta tekrar yüklemeye izin veriliyor.
  Widget _selfieVerificationCard(AppUser user) {
    if (_uploadingSelfie) {
      return GlassCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (user.verified) {
      return GlassCard(
        child: Row(
          children: [
            Icon(Icons.verified_user_rounded, color: AppColors.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Doğrulanmış hesap',
                      style: AppText.subheading.copyWith(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Güven sinyalin eşleşmelerde görünür.',
                      style: AppText.caption),
                ],
              ),
            ),
          ],
        ),
      );
    }
    switch (user.selfieVerificationStatus) {
      case 'pending':
        return GlassCard(
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Selfie doğrulaman inceleniyor',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
              ),
            ],
          ),
        );
      case 'approved':
        return GlassCard(
          child: Row(
            children: [
              Icon(Icons.face_retouching_natural_rounded,
                  color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Selfie doğrulaman onaylandı ✓',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              ),
            ],
          ),
        );
      default:
        // 'none' ya da 'rejected'.
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: _pickAndUploadSelfie,
          child: GlassCard(
            child: Row(
              children: [
                Icon(Icons.face_retouching_natural_outlined,
                    color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    user.selfieVerificationStatus == 'rejected'
                        ? 'Doğrulama reddedildi - tekrar dene'
                        : 'Selfie ile doğrulama rozeti al',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ),
                Icon(Icons.camera_alt_outlined, color: AppColors.textFaint),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildProfileBody(AppUser user) {
    final identityPills = <Widget>[
      if (user.age != null)
        PillBadge(
          label: '${user.age} yaşında',
          color: AppColors.textSecondary,
          icon: Icons.cake_outlined,
        ),
      if (user.gender == 'erkek')
        PillBadge(label: 'Erkek', color: AppColors.textSecondary),
      if (user.gender == 'kadın')
        PillBadge(label: 'Kadın', color: AppColors.textSecondary),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + kToolbarHeight + 20,
        20,
        20,
      ),
      children: [
        _avatarHeader(user),
        const SizedBox(height: AppSpacing.lg),
        _profileCompletionCard(user),
        const SizedBox(height: AppSpacing.md),
        if (user.bio.trim().isNotEmpty || identityPills.isNotEmpty) ...[
          Text('Seni tanıyalım', style: AppText.subheading),
          const SizedBox(height: AppSpacing.sm),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.bio.trim().isNotEmpty) ...[
                  Text(user.bio, style: AppText.body),
                  if (identityPills.isNotEmpty)
                    const SizedBox(height: AppSpacing.md),
                ],
                if (identityPills.isNotEmpty)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: identityPills,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (user.interests.isNotEmpty) ...[
          Text('İlgi alanların', style: AppText.subheading),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: user.interests
                .map((interest) => PillBadge(
                      label: interest,
                      color: AppColors.primaryLight,
                      icon: Icons.interests_outlined,
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (user.profileBadges.isNotEmpty) ...[
          Text('Sana uyan şeyler', style: AppText.subheading),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: user.profileBadges
                .map((badge) => PillBadge(
                      label: _badgeCatalog[badge] ?? badge,
                      color: AppColors.warning,
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Güven', style: AppText.subheading),
        const SizedBox(height: AppSpacing.sm),
        _selfieVerificationCard(user),
        const SizedBox(height: AppSpacing.md),
        Text('Merhaba’da', style: AppText.subheading),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const AchievementsScreen())),
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          color: Colors.amber, size: 20),
                      const SizedBox(height: 8),
                      Text('${user.level}',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      Text('Seviye', style: AppText.caption),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const LeaderboardScreen())),
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.bolt_rounded,
                          color: AppColors.secondary, size: 20),
                      const SizedBox(height: 8),
                      Text('${user.xp}',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      Text('XP · Liderlik tablosu', style: AppText.caption),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (user.introVideoUrl != null) ...[
          _introVideoCard(user),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Hesap', style: AppText.subheading),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(context)
              .push(AppPageRoute(builder: (_) => const SettingsScreen())),
          child: GlassCard(
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Eşleşme ve gizlilik',
                          style: AppText.subheading.copyWith(fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('Kimlerle eşleşeceğini ve görünürlüğünü yönet.',
                          style: AppText.caption),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Çıkış yap'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    // Doldurma rengi/köşe yuvarlaklığı MaterialApp'in InputDecorationTheme'inden
    // geliyor (bkz. theme/app_theme.dart) - burada yalnızca bu alana özgü
    // olanları (etiket, ipucu) belirtiyoruz.
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppColors.textMuted),
      hintStyle: TextStyle(color: AppColors.textFaint),
    );
  }

  Widget _buildEditBody() {
    final user = _authService.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('Profilin karşı tarafa daha iyi bir ilk izlenim versin.',
            style: AppText.body),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: _fieldDecoration('İsim'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bioController,
          maxLines: 3,
          maxLength: 300,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration:
              _fieldDecoration('Hakkımda', hint: 'Kendinden kısaca bahset...'),
        ),
        const SizedBox(height: 6),
        Text('Cinsiyet', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          children: [
            _genderChip('Belirtilmemiş', null),
            _genderChip('Erkek', 'erkek'),
            _genderChip('Kadın', 'kadın'),
          ],
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate:
                  _birthDate ?? DateTime(now.year - 25, now.month, now.day),
              firstDate: AdultAgePolicy.earliestEligibleBirthDate(now),
              lastDate: AdultAgePolicy.latestEligibleBirthDate(now),
            );
            if (picked != null) setState(() => _birthDate = picked);
          },
          child: InputDecorator(
            decoration: _fieldDecoration('Doğum tarihi (18+ doğrulaması)'),
            child: Text(
              _birthDate == null
                  ? 'Doğum tarihi zorunlu'
                  : AdultAgePolicy.displayDate(_birthDate!),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _countryController,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: _fieldDecoration('Ülke', hint: 'ör. Türkiye'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _languageController,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: _fieldDecoration('Dil', hint: 'ör. Türkçe'),
        ),
        const SizedBox(height: 14),
        Text('İlgi Alanları (en fazla 10)', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in _interests)
              Chip(
                label: Text(tag,
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                deleteIcon:
                    Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                onDeleted: () => setState(() => _interests.remove(tag)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _interestController,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: _fieldDecoration('Yeni ilgi alanı ekle'),
                onSubmitted: (_) => _addInterest(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _addInterest,
              icon: Icon(Icons.add_circle, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Profil Rozetleri (en fazla 3)', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _badgeCatalog.entries.map((entry) {
            final selected = _selectedBadges.contains(entry.key);
            return ChoiceChip(
              label: Text(entry.value, style: const TextStyle(fontSize: 12)),
              selected: selected,
              selectedColor: AppColors.primary.withValues(alpha: 0.4),
              backgroundColor: AppColors.textPrimary.withValues(alpha: 0.05),
              labelStyle: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary),
              onSelected: (value) {
                setState(() {
                  if (value) {
                    if (_selectedBadges.length < 3) {
                      _selectedBadges.add(entry.key);
                    }
                  } else {
                    _selectedBadges.remove(entry.key);
                  }
                });
              },
            );
          }).toList(),
        ),
        if (user != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Tanıtım videosu', style: AppText.subheading),
          const SizedBox(height: AppSpacing.sm),
          _introVideoCard(user),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _saving ? null : () => setState(() => _editing = false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.divider),
                ),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                height: 48,
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Kaydet', style: AppText.button),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _genderChip(String label, String? value) {
    final selected = _gender == value;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 12)),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.textPrimary.withValues(alpha: 0.05),
      onSelected: (_) => setState(() => _gender = value),
    );
  }
}
