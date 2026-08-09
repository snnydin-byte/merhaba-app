import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/match_preferences_repository.dart'
    show matchTextOnlyPrefKey;
import '../services/webrtc_service.dart';
import '../widgets/auth_session_builder.dart';
import '../widgets/connection_status_banner.dart';
import '../theme/app_theme.dart';
import '../utils/online_status.dart';
import '../widgets/warm_signal_mark.dart';
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
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _onlineCount = parseOnlineCount(data);
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

  // Kompozisyon: önceki "her şey dikeyde ortalanmış tek sütun" yerine, tek
  // büyük dikdörtgen bir "hero" kart (görüşme CTA'sı bunun İÇİNDE, tam
  // kaplıyor) + kartın altında yatay bir hızlı-erişim rafı (Arkadaşlar/
  // Keşfet/Canlı, daire ikon+etiket - hikaye/story rafı gibi ama gerçek
  // navigasyon hedefleri için). Grup görüşmesi girişi artık ayrı bir buton
  // değil, hero kartın sağ-üst köşesinde küçük bir rozet/chip.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              children: [
                AuthSessionBuilder(
                  builder: (context, _, user) => _buildTopBar(context, user),
                ),
                const ConnectionStatusBanner(),
                const SizedBox(height: 18),
                Expanded(child: _buildHeroCard(context)),
                const SizedBox(height: 16),
                _buildQuickAccessRail(context),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxHeight < 520;
        final logoSize = (constraints.maxWidth * 0.34)
            .clamp(isCompact ? 112.0 : 124.0, 146.0)
            .toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment(0, isCompact ? -0.26 : -0.16),
                child: Container(
                  width: logoSize,
                  height: logoSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(logoSize / 4),
                    boxShadow: neonGlow(
                      const Color(0xFFFFB26B),
                      opacity: 0.22,
                      blurRadius: 36,
                      spreadRadius: 1,
                    ),
                  ),
                  child: WarmSignalMark(size: logoSize),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Yeni biriyle tanış',
                      textAlign: TextAlign.center,
                      style: AppText.display.copyWith(
                        fontSize: isCompact ? 30 : 32,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dünyanın her yerinden insanlarla rastgele görüntülü sohbet et.',
                      textAlign: TextAlign.center,
                      style: AppText.body,
                    ),
                    const SizedBox(height: 18),
                    _buildStartButton(context),
                    const SizedBox(height: 12),
                    _buildGroupCallEntry(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessRail(BuildContext context) {
    final items = <(IconData, String, Color, VoidCallback)>[
      (
        Icons.people_alt_rounded,
        'Arkadaşlar',
        AppColors.primaryLight,
        () => Navigator.of(context)
            .push(AppPageRoute(builder: (_) => const FriendsScreen())),
      ),
      if (AuthService().isLoggedIn) ...[
        (
          Icons.favorite_rounded,
          'Keşfet',
          Colors.pinkAccent,
          () => Navigator.of(context)
              .push(AppPageRoute(builder: (_) => const DiscoverScreen())),
        ),
        (
          Icons.live_tv_rounded,
          'Canlı',
          AppColors.danger,
          () => Navigator.of(context)
              .push(AppPageRoute(builder: (_) => const LiveRoomListScreen())),
        ),
      ],
    ];
    return SizedBox(
      height: 76,
      child: Row(
        children: items
            .map((item) => Expanded(
                  child: GestureDetector(
                    onTap: item.$4,
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surface,
                            border: Border.all(
                                color: item.$3.withValues(alpha: 0.5)),
                          ),
                          child: Icon(item.$1, color: item.$3, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(item.$2,
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AppUser? user) {
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
              icon:
                  Icon(Icons.settings_outlined, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStartButton(BuildContext context) {
    return GradientButton(
      gradient: AppGradients.warmSignal,
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
            AppPageRoute(
                builder: (_) => const VideoChatScreen(textOnlyMode: true)),
          );
        } else {
          Navigator.of(context).push(
            AppPageRoute(builder: (_) => const PreCallScreen()),
          );
        }
      },
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

  // Birincil eşleşme eyleminin altında, aynı görsel dilde grup sohbeti girişi.
  Widget _buildGroupCallEntry(BuildContext context) {
    return GradientButton(
      gradient: AppGradients.liveAccent,
      onPressed: () {
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const GroupCallPreScreen()),
        );
      },
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_rounded, color: Colors.white, size: 21),
          SizedBox(width: 10),
          Text('3–8 kişiyle rastgele eşleş', style: AppText.button),
        ],
      ),
    );
  }
}
