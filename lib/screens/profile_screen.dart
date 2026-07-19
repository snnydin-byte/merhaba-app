import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/messaging_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Giriş yapmış kullanıcı için profil bilgileri (isim, biyografi, cinsiyet,
/// yaş, ilgi alanları, ülke/dil - hepsi düzenlenebilir; e-posta salt-okunur)
/// ve çıkış yap; misafirse giriş/kayda yönlendirir.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _ageController = TextEditingController();
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

  bool _uploadingPhoto = false;
  bool _uploadingVideo = false;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _ageController.dispose();
    _countryController.dispose();
    _languageController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  void _loadFieldsFromUser(AppUser user) {
    _nameController.text = user.displayName;
    _bioController.text = user.bio;
    _ageController.text = user.age?.toString() ?? '';
    _countryController.text = user.country ?? '';
    _languageController.text = user.language ?? '';
    _gender = user.gender;
    _interests = List.of(user.interests);
    _birthDate = user.birthDate != null ? DateTime.tryParse(user.birthDate!) : null;
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
    final choice = await showModalBottomSheet<String>(
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
              leading: const Icon(Icons.photo_library_outlined,
                  color: Colors.white70),
              title: const Text('Galeriden Seç',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            if (user.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.danger),
                title: const Text('Fotoğrafı Kaldır',
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
    }
  }

  // Profil GÖRÜNTÜLEME ekranında ayrı bir hata metni alanı yok (o sadece
  // düzenleme formunda var, bkz. _buildEditBody/_error) - foto işlemleri
  // view modundan tetiklendiği için hataları kısa bir SnackBar ile
  // gösteriyoruz.
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('Video açılamadı.');
    }
  }

  Future<void> _saveProfile() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      setState(() => _error = 'İsim boş olamaz.');
      return;
    }

    int? age;
    final ageText = _ageController.text.trim();
    if (ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age < 13 || age > 120) {
        setState(() => _error = 'Yaş 13 ile 120 arasında olmalı.');
        return;
      }
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
        age: age,
        birthDate: _birthDate == null
            ? null
            : '${_birthDate!.year.toString().padLeft(4, '0')}-'
                '${_birthDate!.month.toString().padLeft(2, '0')}-'
                '${_birthDate!.day.toString().padLeft(2, '0')}',
      );
      if (mounted) setState(() => _editing = false);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Beklenmeyen bir hata oluştu, tekrar dene.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    // Bu cihazın push token'ını hesaptan ayırıyoruz - AuthService.logout()
    // öncesi çağrılmalı, çünkü unregisterCurrentToken() hâlâ geçerli bir
    // auth token'a ihtiyaç duyuyor (sunucuya "kimim" demesi için).
    await PushNotificationService().unregisterCurrentToken();
    // Mesajlaşma/arama sinyal bağlantıları artık uygulama boyunca kalıcı
    // (bkz. messaging_service.dart, call_service.dart) - çıkış yapılırken
    // bunları da gerçekten kapatmamız gerekiyor, aksi halde eski hesabın
    // token'ıyla açık bir bağlantı arkada kalır.
    MessagingService().disconnectSocket();
    CallService().disconnectSocket();
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Profil'),
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
    );
  }

  Widget _buildGuestBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, color: Colors.white38, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Misafir olarak geziniyorsun',
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
              child: Text('Giriş Yap / Hesap Oluştur', style: AppText.button),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarHeader(AppUser user) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showPhotoOptions(user),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl != null
                      ? null
                      : Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
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
                    decoration: const BoxDecoration(
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
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.displayName, style: AppText.subheading),
              if (user.verified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded,
                    color: AppColors.secondary, size: 18),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(user.email, style: AppText.caption),
          if (user.verified) ...[
            const SizedBox(height: AppSpacing.xs),
            PillBadge(label: 'Onaylı hesap', color: AppColors.secondary),
          ],
          // Günlük giriş serisi (GECE_GELISTIRME madde 7) - saf görsel bir
          // rozet, HİÇBİR parasal ödül YOK. 1 günlük seri gösterilmiyor
          // (henüz "seri" sayılmaz, yalnızca bugün giriş yapılmış demek).
          if (user.loginStreak > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            PillBadge(
              label: '${user.loginStreak} günlük seri 🔥',
              color: AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  /// Premium katman DATA MODELİ (Batch C) - gerçek bir ödeme akışı henüz
  /// YOK, bu yüzden [user.isPremium] şu an her zaman false. Kart, ileride
  /// gerçek bir ödeme sağlayıcısı eklenene kadar yalnızca "Yakında" bilgisi
  /// veriyor - kilitli özellik vaadi vermiyor ki gerçekleşmeyen bir söz
  /// olmasın.
  Widget _premiumBanner(AppUser user) {
    if (user.isPremium) {
      return GlassCard(
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded, color: AppColors.warning),
            const SizedBox(width: 10),
            Text('Premium üyesin', style: AppText.subheading.copyWith(fontSize: 14)),
          ],
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Premium', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Premium üyelik yakında geliyor: sınırsız hızlı tur, gelişmiş filtreler ve daha fazlası.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
          ],
        ),
      ),
      child: GlassCard(
        child: Row(
          children: [
            Icon(Icons.workspace_premium_outlined, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Premium - Yakında',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  /// Video/kısa klip profil tanıtımı (Batch C) - en fazla 30sn, galeriden
  /// seçilir, Cloudinary'ye yüklenir (bkz. auth_service.dart
  /// uploadIntroVideo). Oynatma cihazın kendi video oynatıcısında/
  /// tarayıcısında açılır (bkz. _playIntroVideo notu).
  Widget _introVideoCard(AppUser user) {
    if (_uploadingVideo) {
      return const GlassCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
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
              const Icon(Icons.add, color: Colors.white38),
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
              child: const Icon(Icons.play_arrow_rounded, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Video tanıtımın', style: AppText.subheading.copyWith(fontSize: 14)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
            onPressed: _removeIntroVideo,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileBody(AppUser user) {
    final genderLabel = user.gender == 'erkek'
        ? 'Erkek'
        : (user.gender == 'kadın' ? 'Kadın' : 'Belirtilmemiş');
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        // `extendBodyBehindAppBar: true` gövdeyi (bu ListView'i) şeffaf
        // AppBar'ın ARKASINA/ALTINA kadar uzatıyor (gradyan arka planın
        // durum çubuğunun altına kadar sürmesi için, bkz. build()). Ama bu,
        // AppBar'ın kendi (görünmez olsa da hâlâ dokunuşları yakalayan)
        // dikdörtgen alanının ListView'in en üstündeki içerikle ÇAKIŞMASINA
        // yol açıyor - avatar tam bu bölgede olduğu için `onTap` HİÇ
        // tetiklenmiyordu (AppBar dokunuşu sessizce yutuyordu, ne hata ne
        // görsel bir belirti vardı). Avatarı AppBar'ın gerçek yüksekliğinin
        // (durum çubuğu + araç çubuğu) altına itiyoruz.
        MediaQuery.of(context).padding.top + kToolbarHeight + 20,
        20,
        20,
      ),
      children: [
        _avatarHeader(user),
        const SizedBox(height: AppSpacing.xl),
        _infoCard(
            label: 'Hakkımda',
            value: user.bio.isEmpty ? 'Henüz bir şey yazılmamış.' : user.bio),
        _infoCard(label: 'Cinsiyet', value: genderLabel),
        _infoCard(label: 'Yaş', value: user.age?.toString() ?? 'Belirtilmemiş'),
        if (user.zodiac != null)
          _infoCard(label: 'Burç', value: user.zodiac!),
        _infoCard(
          label: 'İlgi Alanları',
          value: user.interests.isEmpty
              ? 'Henüz eklenmemiş.'
              : user.interests.join(', '),
        ),
        _infoCard(
            label: 'Ülke',
            value: user.country?.isNotEmpty == true
                ? user.country!
                : 'Belirtilmemiş'),
        _infoCard(
            label: 'Dil',
            value: user.language?.isNotEmpty == true
                ? user.language!
                : 'Belirtilmemiş'),
        const SizedBox(height: AppSpacing.md),
        _introVideoCard(user),
        const SizedBox(height: AppSpacing.md),
        _premiumBanner(user),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: const Text('Çıkış Yap'),
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
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
    );
  }

  Widget _buildEditBody() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: _fieldDecoration('İsim'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bioController,
          maxLines: 3,
          maxLength: 300,
          style: const TextStyle(color: Colors.white, fontSize: 14),
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
        TextField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: _fieldDecoration('Yaş'),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _birthDate ?? DateTime(now.year - 20, now.month, now.day),
              firstDate: DateTime(now.year - 100),
              lastDate: DateTime(now.year - 13, now.month, now.day),
            );
            if (picked != null) setState(() => _birthDate = picked);
          },
          child: InputDecorator(
            decoration: _fieldDecoration('Doğum tarihi (burcun için)'),
            child: Text(
              _birthDate == null
                  ? 'Seçilmedi'
                  : '${_birthDate!.day.toString().padLeft(2, '0')}.'
                      '${_birthDate!.month.toString().padLeft(2, '0')}.'
                      '${_birthDate!.year}',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _countryController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: _fieldDecoration('Ülke', hint: 'ör. Türkiye'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _languageController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
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
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                deleteIcon:
                    const Icon(Icons.close, size: 14, color: Colors.white70),
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
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _fieldDecoration('Yeni ilgi alanı ekle'),
                onSubmitted: (_) => _addInterest(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _addInterest,
              icon: const Icon(Icons.add_circle, color: AppColors.primary),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _saving ? null : () => setState(() => _editing = false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
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
                    : Text('Kaydet', style: AppText.button),
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
              color: selected ? Colors.white : Colors.white70, fontSize: 12)),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      onSelected: (_) => setState(() => _gender = value),
    );
  }
}
