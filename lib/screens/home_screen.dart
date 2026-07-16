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
    await pushAppRoute(context, (_) => const ProfileScreen());
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
                const _FloatingIllustration(),
                const SizedBox(height: 28),
                const Text('Yeni biriyle tanış', style: AppText.display),
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
                  style: AppText.caption.copyWith(color: AppColors.textFaint),
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
                ? const PulsingDot(color: Colors.greenAccent, size: 8)
                : Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Colors.grey, shape: BoxShape.circle),
                  ),
            const SizedBox(width: 6),
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
                child: user != null
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
                        color: Colors.white70, size: 18),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                pushAppRoute(context, (_) => const SettingsScreen());
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
        onTap: () => pushAppRoute(context, (_) => const FriendsScreen()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_alt_rounded,
                  color: AppColors.primaryLight, size: 16),
              SizedBox(width: 6),
              Text('Arkadaşlar', style: AppText.subheading),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton(BuildContext context) {
    return GradientButton(
      onPressed: () => pushAppRoute(context, (_) => const PreCallScreen()),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_rounded, color: Colors.white),
          SizedBox(width: 10),
          Text('Sohbete Başla', style: AppText.button),
        ],
      ),
    );
  }
}

/// Ana ekrandaki dünya ikonu - önceden sabit duran bir daireydi, artık
/// yavaşça yukarı-aşağı süzülüp hafifçe nefes alır gibi büyüyüp küçülüyor.
/// Bu, "Sohbete Başla" ekranının canlı/davetkar hissetmesine küçük ama
/// etkili bir katkı sağlıyor.
class _FloatingIllustration extends StatefulWidget {
  const _FloatingIllustration();

  @override
  State<_FloatingIllustration> createState() => _FloatingIllustrationState();
}

class _FloatingIllustrationState extends State<_FloatingIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final dy = -8 * t;
        final scale = 1.0 + (0.03 * t);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
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
      ),
    );
  }
}
