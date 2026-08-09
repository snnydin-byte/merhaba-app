import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/warm_signal_mark.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideNextScreen();
  }

  Future<void> _decideNextScreen() async {
    final authService = AuthService();
    final minSplashDuration =
        Future.delayed(const Duration(milliseconds: 1600));

    try {
      // Platform storage veya ağ katmanı başlangıçta yanıt vermezse splash
      // ekranını sonsuza kadar açık bırakma. Saklı oturum okunamazsa güvenli
      // varsayım signed-out durumudur; kullanıcı login ekranından devam eder.
      final hasStoredSession = await authService
          .restoreSession()
          .timeout(const Duration(seconds: 12));
      if (hasStoredSession) {
        await authService.verifySession().timeout(const Duration(seconds: 12));
      }
    } catch (error, stackTrace) {
      debugPrint('Splash oturum başlangıcı tamamlanamadı: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // Açılış animasyonunun en az 1600ms sürmesini garantiliyoruz ama bunu
    // oturum kontrolüyle aynı anda bekliyoruz (üst üste eklemiyoruz).
    await minSplashDuration;
    if (!mounted) return;

    final nextScreen =
        authService.isLoggedIn ? const HomeScreen() : const LoginScreen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => nextScreen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Canva neon dark-mode mockup'ında splash düz, neredeyse tam siyah
        // (gradyan görünmüyor) - backgroundDeep tek renk burada gradyandan
        // daha sadık.
        color: AppColors.backgroundDeep,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Hafif bir "pop" (büyüyerek belirme) girişi - önceden logo
              // ekranla birlikte aniden beliriyordu, bu küçük dokunuş açılışı
              // daha "canlı" hissettiriyor.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (context, value, child) => Transform.scale(
                  scale: value.clamp(0, 1.15),
                  child: Opacity(opacity: value.clamp(0, 1), child: child),
                ),
                child: const WarmSignalMark(size: 168),
              ),
              const SizedBox(height: 28),
              Text(
                'MERHABA',
                style: AppText.display.copyWith(letterSpacing: 6),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFFFFB26B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
