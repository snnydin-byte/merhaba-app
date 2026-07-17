import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import '../utils/online_status.dart';
import 'friends_screen.dart';
import 'pre_call_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _onlineCount;
  bool _serverReachable = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchOnlineCount();
    // Sunucu çalışırken kullanıcıya güncel kalsın diye periyodik yeniliyoruz;
    // sunucu kapalıysa istekler sessizce başarısız olur, uygulamayı kilitlemez.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchOnlineCount(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOnlineCount() async {
    try {
      final response = await http
          .get(Uri.parse('$signalingServerUrl/status'))
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _onlineCount = data['onlineCount'] as int?;
          _serverReachable = _onlineCount != null;
        });
      } else {
        setState(() => _serverReachable = false);
      }
    } catch (_) {
      // Sunucu kapalı olabilir (geliştirme ortamında bu normal) - sahte bir
      // sayı göstermek yerine durumu dürüstçe yansıtıyoruz, bkz. KURULUM.md.
      if (mounted) setState(() => _serverReachable = false);
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => const ProfileScreen()),
    );
    // Profil ekranından dönünce (ör. çıkış yapılmış olabilir) üst çubuğun
    // güncel oturum durumunu göstermesi için yeniden çiziyoruz.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                _buildTopBar(context),
                const SizedBox(height: 12),
                _buildFriendsEntry(context),
                const Spacer(),
                _buildCenterIllustration(),
                const SizedBox(height: 28),
                Text(
                  'Yeni biriyle tanış',
                  style: AppText.heading.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  'Dünyanın her yerinden insanlarla\nrastgele görüntülü sohbet et.',
                  textAlign: TextAlign.center,
                  style: AppText.body,
                ),
                const Spacer(),
                _buildStartButton(context),
                const SizedBox(height: 12),
                Text(
                  'Devam ederek Topluluk Kurallarını kabul etmiş olursun.',
                  textAlign: TextAlign.center,
                  style: AppText.caption,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final user = AuthService().currentUser;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _serverReachable
                ? const PulsingDot(color: AppColors.secondary, size: 8)
                : Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
            const SizedBox(width: 8),
            Text(
              onlineCountLabel(_serverReachable ? _onlineCount : null),
              style: AppText.caption.copyWith(fontSize: 13),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _openProfile,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                backgroundImage: user?.photoUrl != null
                    ? NetworkImage(user!.photoUrl!)
                    : null,
                child: user?.photoUrl != null
                    ? null
                    : (user != null
                        ? Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          )
                        : const Icon(Icons.person_outline,
                            color: Colors.white70, size: 18)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  /// Çevrimiçi sayısının hemen altında yer alan "Arkadaşlar" girişi.
  /// Misafir kullanıcılar da dokunabilir - arkadaşlar ekranı kendi
  /// içinde giriş yapmasını isteyen bir durum gösterir (bkz.
  /// friends_screen.dart).
  Widget _buildFriendsEntry(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            AppPageRoute(builder: (_) => const FriendsScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.primaryLight, size: 16),
              const SizedBox(width: 6),
              Text(
                'Arkadaşlar',
                style: AppText.subheading.copyWith(fontSize: 13),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterIllustration() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.25),
            AppColors.secondary.withValues(alpha: 0.15),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.public_rounded,
            color: AppColors.primaryLight, size: 80),
      ),
    );
  }

  Widget _buildStartButton(BuildContext context) {
    return GradientButton(
      onPressed: () {
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const PreCallScreen()),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text('Sohbete Başla', style: AppText.button),
        ],
      ),
    );
  }
}
