import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Uygulamanın marka işareti - "Bağlantı Zinciri" logosu (bkz. android/ios/
/// macos/web ikon dosyaları, aynı geometri: üç düğüm + iki video-görüşme
/// kavsi). Marka rengi BİLEREK sabit (tema-bağımsız) - AppColors.primary/
/// secondary kullanılan tema ile değişebilir ama logonun kendisi her temada
/// aynı kimliği taşımalı, tıpkı uygulama ikonunun tema seçiminden
/// etkilenmemesi gibi. splash_screen.dart ve home_screen.dart tarafından
/// paylaşılıyor - koordinatlar ikon üretiminde kullanılan 296x200 SVG
/// viewBox'ıyla birebir aynı.
///
/// Widget mount olduğunda BİR KEZ (kavisler çizilir, düğümler sırayla
/// belirir, oynat işaretleri son olarak solar) giriş animasyonu oynatır,
/// sonra sabit son haline oturur - sürekli dönen/nabız atan bir döngü
/// YOK (her açılışta/ana ekranda sürekli hareket dikkat dağıtır). Sistem
/// "hareketi azalt" ayarı açıksa animasyon hiç oynatılmaz, doğrudan son
/// hâliyle görünür.
class ConnectionMark extends StatefulWidget {
  const ConnectionMark({super.key, required this.width});

  final double width;

  @override
  State<ConnectionMark> createState() => _ConnectionMarkState();
}

class _ConnectionMarkState extends State<ConnectionMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    final reduceMotion =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.width * 200 / 296,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConnectionMarkPainter(_controller.value),
        ),
      ),
    );
  }
}

class _ConnectionMarkPainter extends CustomPainter {
  _ConnectionMarkPainter(this.t);

  final double t;

  static const _violet = Color(0xFF9575FF);
  static const _turquoise = Color(0xFF3DE0C4);

  // Giriş animasyonu zaman çizelgesi (0..1 toplam süre üzerinden):
  // kavisler önce çizilir, dış düğümler kavis ucuna ulaşınca belirir,
  // orta düğüm ikisi birleşince belirir, oynat işaretleri en son solar.
  static const _archInterval = Interval(0.0, 0.55, curve: Curves.easeOut);
  static const _outerNodeInterval = Interval(0.30, 0.60, curve: Curves.elasticOut);
  static const _centerNodeInterval = Interval(0.45, 0.75, curve: Curves.elasticOut);
  static const _markerInterval = Interval(0.60, 1.0, curve: Curves.easeOut);

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

    final fullArches = Path()
      ..moveTo(52, 140)
      ..quadraticBezierTo(100, 40, 148, 140)
      ..quadraticBezierTo(196, 40, 244, 140);

    final archProgress = _archInterval.transform(t).clamp(0.0, 1.0);
    final archPaint = Paint()
      ..shader = gradientShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    if (archProgress >= 1) {
      canvas.drawPath(fullArches, archPaint);
    } else if (archProgress > 0) {
      final metric = fullArches.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * archProgress),
        archPaint,
      );
    }

    void drawNode(Offset center, Color color, double rawT) {
      // clamp yok: elasticOut kasıtlı olarak 1.0'ı aşıp geri oturuyor
      // ("pop" hissi) - üst sınırı kessek bu sekmeyi düzleştirirdik.
      final scale = _outerNodeInterval.transform(rawT);
      if (scale <= 0) return;
      canvas.drawCircle(center, 14 * scale, Paint()..color = color);
    }

    drawNode(const Offset(52, 140), _violet, t);
    drawNode(const Offset(244, 140), _violet, t);
    final centerScale = _centerNodeInterval.transform(t);
    if (centerScale > 0) {
      canvas.drawCircle(const Offset(148, 140), 14 * centerScale, Paint()..color = _turquoise);
    }

    final markerT = _markerInterval.transform(t).clamp(0.0, 1.0);
    if (markerT > 0) {
      final ringPaint = Paint()
        ..shader = gradientShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: markerT);
      canvas.drawCircle(const Offset(100, 104), 15 * (0.7 + 0.3 * markerT), ringPaint);
      canvas.drawCircle(const Offset(196, 104), 15 * (0.7 + 0.3 * markerT), ringPaint);

      final trianglePaint = Paint()..color = Colors.white.withValues(alpha: markerT);
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
  }

  @override
  bool shouldRepaint(covariant _ConnectionMarkPainter oldDelegate) => oldDelegate.t != t;
}
