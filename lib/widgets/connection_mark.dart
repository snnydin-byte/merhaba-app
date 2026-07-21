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
class ConnectionMark extends StatelessWidget {
  const ConnectionMark({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 200 / 296,
      child: const CustomPaint(painter: _ConnectionMarkPainter()),
    );
  }
}

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
