import 'package:flutter/material.dart';

/// Merhaba'nın uygulama genelinde paylaşılan görsel dili (renkler,
/// gradyanlar, yazı stilleri, tekrar kullanılabilir bileşenler).
///
/// NEDEN BU DOSYA: önceden her ekran kendi rengini/boşluğunu/köşe
/// yuvarlaklığını elle tekrar yazıyordu (ör. `Color(0xFF7C4DFF)` onlarca
/// yerde tekrarlanıyordu) - bu hem tutarsızlığa (bir yerde 18, başka yerde
/// 20 köşe yarıçapı gibi) hem de bir renk/stil değiştirmek istendiğinde
/// onlarca dosyayı tek tek düzeltme zorunluluğuna yol açıyordu. Artık her
/// ekran bu dosyadaki sabitleri/bileşenleri kullanıyor - "Azar tarzı" koyu
/// tema + canlı mor/turkuaz gradyan kimliği TEK YERDEN yönetiliyor.
class AppColors {
  AppColors._();

  // Zemin katmanları - düz tek renk yerine hafif bir derinlik hissi için
  // birden fazla ton (bkz. AppGradients.background).
  static const background = Color(0xFF0B0B16);
  static const backgroundDeep = Color(0xFF07070F);
  static const surface = Color(0xFF15121F);
  static const surfaceElevated = Color(0xFF1B1830);
  static const surfaceBorder = Color(0x1FFFFFFF); // white @ 12%

  static const primary = Color(0xFF7C4DFF); // mor
  static const primaryLight = Color(0xFF9575FF);
  static const secondary = Color(0xFF00BFA5); // turkuaz
  static const secondaryLight = Color(0xFF3DE0C4);
  static const danger = Color(0xFFFF5470);
  static const warning = Color(0xFFFFB74D);

  static const textPrimary = Colors.white;
  static Color textSecondary = Colors.white.withValues(alpha: 0.7);
  static Color textMuted = Colors.white.withValues(alpha: 0.45);
  static Color textFaint = Colors.white.withValues(alpha: 0.3);
  static Color divider = Colors.white.withValues(alpha: 0.08);
}

class AppGradients {
  AppGradients._();

  /// Ana marka gradyanı - CTA butonları, aktif durumlar, seçili sekmeler.
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, Color(0xFF6A3DE8)],
  );

  /// "Canlı/bağlandı" durumları için mor->turkuaz - eşleşme bulunduğunda,
  /// aktif görüşme rozetlerinde kullanılır.
  static const liveAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.secondary],
  );

  /// Tüm ekranların arka planında kullanılan çok hafif, neredeyse
  /// fark edilmeyen derinlik gradyanı - düz tek renkten daha "premium"
  /// hissettirir ama dikkat dağıtmaz.
  static const background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.background, AppColors.backgroundDeep],
  );

  static LinearGradient softGlow(Color color, {double opacity = 0.25}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 0.4),
      ],
    );
  }
}

class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppText {
  AppText._();

  static const _fontFamily = 'Roboto';

  static const display = TextStyle(
    fontFamily: _fontFamily,
    color: AppColors.textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const heading = TextStyle(
    fontFamily: _fontFamily,
    color: AppColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const subheading = TextStyle(
    fontFamily: _fontFamily,
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    color: AppColors.textSecondary,
    fontSize: 14,
    height: 1.45,
  );

  static TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    color: AppColors.textMuted,
    fontSize: 12,
  );

  static const button = TextStyle(
    fontFamily: _fontFamily,
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );
}

/// Uygulama genelinde ekranların arka planı - hafif gradyan + üstte belli
/// belirsiz iki "glow" (ışık lekesi) ile düz renkten daha derinlikli bir
/// his verir. `child`, normal ekran içeriğidir.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.background),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Glow(color: AppColors.primary.withValues(alpha: 0.16)),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child:
                _Glow(color: AppColors.secondary.withValues(alpha: 0.10)),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  const _Glow({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Marka gradyanlı, yuvarlak birincil buton - "Sohbete Başla", "Giriş Yap"
/// gibi ekranın ana eylemi için. Devre dışıyken (onPressed: null) gradyan
/// soluklaşır.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  final Gradient gradient;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 58,
    this.gradient = AppGradients.primary,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: onPressed,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hafif cam/kart yüzeyi - koyu zemin üzerinde ince kenarlıklı, hafif
/// aydınlık bir yüzey hissi verir (formlar, listeler, bilgi kartları).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.radius = AppRadius.md,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: child,
    );
  }
}

/// Küçük durum/etiket rozeti (ör. "CANLI", "Onaylı", kategori etiketleri).
class PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const PillBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yavaşça büyüyüp küçülen bir nokta - "eşleşme aranıyor"/"çevrimiçi" gibi
/// canlı/aktif durumları düz bir noktadan daha "yaşıyor" hissettirmek için.
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulsingDot({super.key, required this.color, this.size = 10});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
      builder: (context, _) {
        final scale = 1.0 + (_controller.value * 0.5);
        final glowOpacity = (1 - _controller.value) * 0.5;
        return SizedBox(
          width: widget.size * 2.2,
          height: widget.size * 2.2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: glowOpacity),
                  ),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tüm uygulama boyunca kullanılan sayfa geçişi - varsayılan Material
/// "sağdan kaydır"ın yerine hafif bir solma + yukarı doğru kayma (daha
/// yumuşak/modern bir his, Azar/Omegle tarzı uygulamalarda yaygın).
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;
  AppPageRoute({required this.builder})
      : super(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// `Navigator.of(context).push(MaterialPageRoute(builder: ...))` çağrılarını
/// kısaltan ve hepsine aynı özel geçiş animasyonunu (bkz. AppPageRoute)
/// uygulayan yardımcı fonksiyon.
Future<T?> pushAppRoute<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context).push<T>(AppPageRoute<T>(builder: builder));
}

/// ThemeData.pageTransitionsTheme'e takılır - bu sayede uygulama genelinde
/// zaten var olan TÜM `Navigator.push(MaterialPageRoute(...))` çağrıları
/// (onlarca ekranda tek tek değiştirmeye gerek kalmadan) otomatik olarak
/// AppPageRoute'daki aynı solma + hafif yukarı kayma geçişini kullanır.
class _AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

final appPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: const _AppPageTransitionsBuilder(),
    TargetPlatform.iOS: const _AppPageTransitionsBuilder(),
    TargetPlatform.macOS: const _AppPageTransitionsBuilder(),
    TargetPlatform.windows: const _AppPageTransitionsBuilder(),
    TargetPlatform.linux: const _AppPageTransitionsBuilder(),
  },
);

/// Uygulamanın tam ThemeData'sı - main.dart'ta MaterialApp'e verilir.
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
    fontFamily: 'Roboto',
    pageTransitionsTheme: appPageTransitionsTheme,
    textTheme: const TextTheme(
      displayLarge: AppText.display,
      headlineSmall: AppText.heading,
      titleMedium: AppText.subheading,
      bodyMedium: TextStyle(color: AppColors.textPrimary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        textStyle: AppText.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
  );
}
