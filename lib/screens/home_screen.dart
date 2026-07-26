import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import '../utils/online_status.dart';
import '../widgets/connection_mark.dart';
import 'discover_screen.dart';
import 'friends_screen.dart';
import 'group_call_pre_screen.dart';
import 'live_room_list_screen.dart';
import 'pre_call_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'video_chat_screen.dart';

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
                const SizedBox(height: 10),
                _buildGroupCallEntry(context),
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
                ? PulsingDot(color: AppColors.secondary, size: 8)
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
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          )
                        : Icon(Icons.person_outline,
                            color: AppColors.textSecondary, size: 18)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pillEntry(
            context,
            icon: Icons.people_alt_rounded,
            label: 'Arkadaşlar',
            onTap: () => Navigator.of(context)
                .push(AppPageRoute(builder: (_) => const FriendsScreen())),
          ),
          // Keşfet (Batch E, Dating katmanı) - misafir kullanıcılara
          // gösterilmiyor, DiscoverService REST çağrıları giriş yapılmış
          // bir JWT token gerektiriyor.
          if (AuthService().isLoggedIn) ...[
            const SizedBox(width: 8),
            _pillEntry(
              context,
              icon: Icons.favorite_rounded,
              label: 'Keşfet',
              iconColor: Colors.pinkAccent,
              onTap: () => Navigator.of(context)
                  .push(AppPageRoute(builder: (_) => const DiscoverScreen())),
            ),
            const SizedBox(width: 8),
            _pillEntry(
              context,
              icon: Icons.live_tv_rounded,
              label: 'Canlı',
              iconColor: AppColors.danger,
              onTap: () => Navigator.of(context)
                  .push(AppPageRoute(builder: (_) => const LiveRoomListScreen())),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pillEntry(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            Icon(icon, color: iconColor ?? AppColors.primaryLight, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.subheading.copyWith(fontSize: 13),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textFaint, size: 16),
          ],
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
        boxShadow: neonGlow(AppColors.primary, opacity: 0.3, blurRadius: 40, spreadRadius: 8),
      ),
      child: const Center(
        child: ConnectionMark(width: 110),
      ),
    );
  }

  Widget _buildStartButton(BuildContext context) {
    return GradientButton(
      onPressed: () async {
        // Sadece metin modu (Batch C) - açıksa kamera/mikrofon izni HİÇ
        // istenmeden doğrudan metin sohbeti aramaya geçilir (bkz.
        // video_chat_screen.dart textOnlyMode, settings_screen.dart'taki
        // anahtar). Diğer tüm durumlarda PreCallScreen'deki normal önizleme
        // akışı değişmeden devam ediyor.
        final prefs = await SharedPreferences.getInstance();
        final textOnly = prefs.getBool(matchTextOnlyPrefKey) ?? false;
        if (!context.mounted) return;
        if (textOnly) {
          Navigator.of(context).push(
            AppPageRoute(builder: (_) => const VideoChatScreen(textOnlyMode: true)),
          );
        } else {
          Navigator.of(context).push(
            AppPageRoute(builder: (_) => const PreCallScreen()),
          );
        }
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

  // Küçük grup rastgele görüşmesi (mesh, 3-4 kişi, Batch C) - ana CTA'nın
  // altında ikincil, göze daha az çarpan bir giriş. "(beta)" etiketi
  // bilerek kalıcı: bu özellik gerçek çoklu-cihaz testinden geçmedi.
  Widget _buildGroupCallEntry(BuildContext context) {
    return GradientButton(
      height: 48,
      gradient: AppGradients.softGlow(AppColors.secondary, opacity: 0.3),
      onPressed: () {
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const GroupCallPreScreen()),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_rounded, color: AppColors.textPrimary, size: 18),
          const SizedBox(width: 8),
          Text(
            'Grup Görüşmesi (beta) · 3-4 kişi',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
