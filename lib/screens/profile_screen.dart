import 'package:flutter/material.dart';

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
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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
            const SizedBox(height: 16),
            const Text(
              'Misafir olarak geziniyorsun',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Profilini görmek ve düzenlemek için giriş yap ya da bir hesap oluştur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 24),
            GradientButton(
              height: 52,
              onPressed: () {
                pushAppRoute(context, (_) => const LoginScreen());
              },
              child: const Text(
                'Giriş Yap / Hesap Oluştur',
                style: AppText.button,
              ),
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
          CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primary.withValues(alpha: 0.25),
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user.displayName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600),
              ),
              if (user.verified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded,
                    color: AppColors.secondary, size: 18),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          if (user.verified) ...[
            const SizedBox(height: 6),
            const PillBadge(
              label: 'Onaylı hesap',
              color: AppColors.secondary,
              icon: Icons.verified_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBody(AppUser user) {
    final genderLabel = user.gender == 'erkek'
        ? 'Erkek'
        : (user.gender == 'kadın' ? 'Kadın' : 'Belirtilmemiş');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _avatarHeader(user),
        const SizedBox(height: 32),
        _infoCard(
            label: 'Hakkımda',
            value: user.bio.isEmpty ? 'Henüz bir şey yazılmamış.' : user.bio),
        _infoCard(label: 'Cinsiyet', value: genderLabel),
        _infoCard(label: 'Yaş', value: user.age?.toString() ?? 'Belirtilmemiş'),
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
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
            child: const Text('Çıkış Yap'),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
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
        Text('Cinsiyet',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(height: 8),
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
        Text('İlgi Alanları (en fazla 10)',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
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
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _saving ? null : () => setState(() => _editing = false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _saving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Kaydet'),
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
