import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/call_ui_controller.dart';
import '../services/messaging_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_mark.dart';
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

    // Cihazda saklı bir oturum varsa sunucudan doğrula (token süresi dolmuş
    // olabilir). Sunucuya ulaşılamazsa cihazdaki oturumla devam edilir -
    // bkz. AuthService.verifySession.
    final hasStoredSession = await authService.restoreSession();
    if (hasStoredSession) {
      await authService.verifySession();
      // Zaten girişli olarak açılıyorsa (uygulama daha önce kapatılmıştı,
      // şimdi tekrar açıldı) push token'ı da hemen kaydetmeye çalışıyoruz -
      // main.dart'taki PushNotificationService().init() bu noktada muhtemelen
      // tamamlanmış (Firebase yapılandırıldıysa) ya da hâlâ sessizce
      // devredışı (yapılandırılmadıysa, o zaman bu çağrı da no-op).
      if (authService.isLoggedIn) {
        // Push token kaydı (sunucuya ayrı bir HTTP isteği) mesajlaşma/arama
        // soketlerinin açılmasından BAĞIMSIZ - burada await ETMEDEN
        // (fire-and-forget) tetikliyoruz ki soket bağlantıları onun bitmesini
        // beklemesin. Böylece gelen mesaj/arama davetlerinin dinlenmeye
        // başlaması, push token kaydının (bazen yavaş olabilen FCM +
        // sunucu round-trip'i) süresi kadar gecikmiyor.
        // ignore: unawaited_futures
        PushNotificationService().registerTokenWithServer();
        // Mesajlaşma ve arama sinyal bağlantılarını burada, oturum
        // doğrulanır doğrulanmaz BİR KEZ kuruyoruz - artık ekran bazlı
        // değil, uygulama boyunca kalıcılar (bkz. messaging_service.dart,
        // call_service.dart). CallUiController().wire() gelen arama
        // davetlerini hangi ekranda olunursa olsun gösterebilmek için
        // gerekli (bkz. call_ui_controller.dart).
        final token = authService.token;
        if (token != null) {
          MessagingService().connectIfNeeded(token);
          CallService().connectIfNeeded(token);
          CallUiController().wire();
        }
      }
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
                child: const ConnectionMark(width: 168),
              ),
              const SizedBox(height: 28),
              Text(
                'MERHABA',
                style: AppText.display.copyWith(letterSpacing: 6),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
