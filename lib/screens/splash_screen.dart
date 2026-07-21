import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/call_ui_controller.dart';
import '../services/messaging_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
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
        decoration: BoxDecoration(
          // Önceden bir köşesi sabit koyu mor (0xFF1A1035), diğeri
          // AppColors.backgroundDeep idi - tema artık runtime'da değişince bu
          // ikisi uyuşmaz olurdu (açık temalarda tek köşe hâlâ koyu kalırdı).
          // Uygulamanın kendi arka plan gradyanını (AppGradients.background)
          // kullanmak splash'ı her temada tutarlı kılıyor.
          gradient: AppGradients.background,
        ),
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
                child: const SizedBox(
                  width: 168,
                  height: 113.5, // 168 * 200/296 - aynı en-boy oranı (bkz. _ConnectionMarkPainter)
                  child: CustomPaint(painter: _ConnectionMarkPainter()),
                ),
              ),
              const SizedBox(height: 24),
              Text('Merhaba', style: AppText.display),
              const SizedBox(height: 8),
              Text('Dünyayla tanış', style: AppText.body),
              const SizedBox(height: 40),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uygulamanın marka işareti - "Bağlantı Zinciri" logosu (bkz. android/ios/
/// macos/web ikon dosyaları, aynı geometri). Marka rengi BİLEREK sabit
/// (tema-bağımsız) - AppColors.primary/secondary kullanılan tema ile
/// değişebilir ama logonun kendisi her temada aynı kimliği taşımalı, tıpkı
/// uygulama ikonunun tema seçiminden etkilenmemesi gibi. Koordinatlar,
/// ikon üretiminde kullanılan 296x200 SVG viewBox'ıyla birebir aynı.
class _ConnectionMarkPainter extends CustomPainter {
  const _ConnectionMarkPainter();

  static const _violet = Color(0xFF9575FF);
  static const _turquoise = Color(0xFF3DE0C4);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 296;
    canvas.scale(scale);

    final gradientShader = ui.Gradient.linear(
      const Offset(0, 100),
      const Offset(296, 100),
      const [_violet, _turquoise, _violet],
      const [0, 0.5, 1],
    );

    final archPaint = Paint()
      ..shader = gradientShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final arches = Path()
      ..moveTo(52, 140)
      ..quadraticBezierTo(100, 40, 148, 140)
      ..quadraticBezierTo(196, 40, 244, 140);
    canvas.drawPath(arches, archPaint);

    canvas.drawCircle(const Offset(52, 140), 14, Paint()..color = _violet);
    canvas.drawCircle(const Offset(148, 140), 14, Paint()..color = _turquoise);
    canvas.drawCircle(const Offset(244, 140), 14, Paint()..color = _violet);

    final ringPaint = Paint()
      ..shader = gradientShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(100, 104), 15, ringPaint);
    canvas.drawCircle(const Offset(196, 104), 15, ringPaint);

    final trianglePaint = Paint()..color = Colors.white;
    canvas.drawPath(
      Path()
        ..moveTo(92, 94)
        ..lineTo(112, 104)
        ..lineTo(92, 114)
        ..close(),
      trianglePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(188, 94)
        ..lineTo(208, 104)
        ..lineTo(188, 114)
        ..close(),
      trianglePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionMarkPainter oldDelegate) => false;
}
