import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Merhaba'nın uygulama genelinde paylaşılan görsel dili (renkler,
/// gradyanlar, yazı stilleri, tekrar kullanılabilir bileşenler).
///
/// NEDEN BU DOSYA: önceden her ekran kendi rengini/boşluğunu/köşe
/// yuvarlaklığını elle tekrar yazıyordu (ör. `Color(0xFF7C4DFF)` onlarca
/// yerde tekrarlanıyordu) - bu hem tutarsızlığa (bir yerde 18, başka yerde
/// 20 köşe yarıçapı gibi) hem de bir renk/stil değiştirmek istendiğinde
/// onlarca dosyayı tek tek düzeltme zorunluluğuna yol açıyordu. Artık her
/// ekran bu dosyadaki sabitleri/bileşenleri kullanıyor.
///
/// TEMA SEÇİMİ (runtime'da değiştirilebilir): önceden `AppColors` tamamen
/// `static const` idi - text_scale_notifier.dart'taki eski nota göre bu,
/// tam bir tema değişimini runtime'da İMKANSIZ kılıyordu (`const`
/// constructor'lar içinde kullanıldığı için). Bunu çözmek için `AppColors`/
/// `AppText`/`AppGradients` artık `static const` DEĞİL, aktif paleti
/// (`_currentPalette`) okuyan `static get`'ler - dışarıdan bakan API
/// (ör. `AppColors.primary`) AYNI kaldı, hiçbir ekranın import'unu ya da
/// çağrı şeklini değiştirmeye gerek kalmadı. Değişen tek şey: artık bu
/// değerler her okunduğunda GÜNCEL paleti yansıtıyor.
enum AppThemeVariant { dark, playful, trust }

class _Palette {
  final Color background;
  final Color backgroundDeep;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceBorder;
  final Color primary;
  final Color primaryLight;
  final Color secondary;
  final Color secondaryLight;
  final Color danger;
  final Color warning;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;
  final Color divider;
  final Brightness brightness;

  const _Palette({
    required this.background,
    required this.backgroundDeep,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceBorder,
    required this.primary,
    required this.primaryLight,
    required this.secondary,
    required this.secondaryLight,
    required this.danger,
    required this.warning,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.divider,
    required this.brightness,
  });
}

/// "Koyu" - mevcut/varsayılan kimlik ("Azar tarzı" koyu zemin + mor/turkuaz
/// gradyan). Değerler ÖNCEKİ static const'larla birebir aynı - bu paletin
/// varsayılan olması hiçbir görsel değişikliğe yol açmıyor.
final _darkPalette = _Palette(
  background: const Color(0xFF0B0B16),
  backgroundDeep: const Color(0xFF07070F),
  surface: const Color(0xFF15121F),
  surfaceElevated: const Color(0xFF1B1830),
  surfaceBorder: const Color(0x1FFFFFFF),
  primary: const Color(0xFF7C4DFF),
  primaryLight: const Color(0xFF9575FF),
  secondary: const Color(0xFF00BFA5),
  secondaryLight: const Color(0xFF3DE0C4),
  danger: const Color(0xFFFF5470),
  warning: const Color(0xFFFFB74D),
  textPrimary: Colors.white,
  textSecondary: Colors.white.withValues(alpha: 0.7),
  textMuted: Colors.white.withValues(alpha: 0.45),
  textFaint: Colors.white.withValues(alpha: 0.3),
  divider: Colors.white.withValues(alpha: 0.08),
  brightness: Brightness.dark,
);

/// "Oyunlaştırılmış Enerji" - açık, gül/mercan/güneş sarısı, rozet/XP/
/// liderlik tablosu (gamification_service.dart) özellikleriyle örtüşen sıcak
/// ve davetkâr bir yön.
final _playfulPalette = _Palette(
  background: const Color(0xFFFFF1F2),
  backgroundDeep: const Color(0xFFFFE4E7),
  surface: const Color(0xFFFFFFFF),
  surfaceElevated: const Color(0xFFFFFFFF),
  surfaceBorder: const Color(0xFFFECDD3),
  primary: const Color(0xFFE11D48),
  primaryLight: const Color(0xFFFB7185),
  secondary: const Color(0xFFFFC845),
  secondaryLight: const Color(0xFFFFDD8A),
  danger: const Color(0xFFDC2626),
  warning: const Color(0xFFF59E0B),
  textPrimary: const Color(0xFF881337),
  textSecondary: const Color(0xFF881337).withValues(alpha: 0.72),
  textMuted: const Color(0xFF881337).withValues(alpha: 0.5),
  textFaint: const Color(0xFF881337).withValues(alpha: 0.32),
  divider: const Color(0xFF881337).withValues(alpha: 0.1),
  brightness: Brightness.light,
);

/// "Güven & Berraklık" - açık, lacivert/menekşe, güvenlik/gizlilik/
/// doğrulama özelliklerini öne çıkaran sakin ve kurumsal-sıcak bir yön.
final _trustPalette = _Palette(
  background: const Color(0xFFF7F9FC),
  backgroundDeep: const Color(0xFFEDF1F8),
  surface: const Color(0xFFFFFFFF),
  surfaceElevated: const Color(0xFFFFFFFF),
  surfaceBorder: const Color(0xFFE2E8F0),
  primary: const Color(0xFF1E3A8A),
  primaryLight: const Color(0xFF3B5FCB),
  secondary: const Color(0xFF7C6CF0),
  secondaryLight: const Color(0xFF9B8FF5),
  danger: const Color(0xFFDC2626),
  warning: const Color(0xFFF59E0B),
  textPrimary: const Color(0xFF1E293B),
  textSecondary: const Color(0xFF1E293B).withValues(alpha: 0.7),
  textMuted: const Color(0xFF1E293B).withValues(alpha: 0.48),
  textFaint: const Color(0xFF1E293B).withValues(alpha: 0.3),
  divider: const Color(0xFF1E293B).withValues(alpha: 0.1),
  brightness: Brightness.light,
);

_Palette _paletteFor(AppThemeVariant variant) {
  switch (variant) {
    case AppThemeVariant.dark:
      return _darkPalette;
    case AppThemeVariant.playful:
      return _playfulPalette;
    case AppThemeVariant.trust:
      return _trustPalette;
  }
}

/// Aktif tema - basit bir ValueNotifier (text_scale_notifier.dart'taki AYNI
/// desen: Provider/Riverpod gibi bir paket eklemeye gerek yok). main.dart
/// bunu dinleyip `MaterialApp`'i yeniden kurar, settings_screen.dart
/// değiştirir.
final ValueNotifier<AppThemeVariant> appThemeNotifier =
    ValueNotifier<AppThemeVariant>(AppThemeVariant.dark);

const String _appThemePrefKey = 'app_theme_variant';

Future<void> loadAppThemePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_appThemePrefKey);
  appThemeNotifier.value = AppThemeVariant.values.firstWhere(
    (v) => v.name == saved,
    orElse: () => AppThemeVariant.dark,
  );
}

Future<void> setAppThemePreference(AppThemeVariant variant) async {
  appThemeNotifier.value = variant;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_appThemePrefKey, variant.name);
}

class AppColors {
  AppColors._();

  static _Palette get _p => _paletteFor(appThemeNotifier.value);

  static Color get background => _p.background;
  static Color get backgroundDeep => _p.backgroundDeep;
  static Color get surface => _p.surface;
  static Color get surfaceElevated => _p.surfaceElevated;
  static Color get surfaceBorder => _p.surfaceBorder;

  static Color get primary => _p.primary;
  static Color get primaryLight => _p.primaryLight;
  static Color get secondary => _p.secondary;
  static Color get secondaryLight => _p.secondaryLight;
  static Color get danger => _p.danger;
  static Color get warning => _p.warning;

  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;
  static Color get textFaint => _p.textFaint;
  static Color get divider => _p.divider;

  static Brightness get brightness => _p.brightness;
}

class AppGradients {
  AppGradients._();

  /// Ana marka gradyanı - CTA butonları, aktif durumlar, seçili sekmeler.
  static LinearGradient get primary => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary, AppColors.primaryLight],
      );

  /// "Canlı/bağlandı" durumları için birincil->ikincil - eşleşme
  /// bulunduğunda, aktif görüşme rozetlerinde kullanılır.
  static LinearGradient get liveAccent => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary, AppColors.secondary],
      );

  /// Tüm ekranların arka planında kullanılan çok hafif, neredeyse
  /// fark edilmeyen derinlik gradyanı - düz tek renkten daha "premium"
  /// hissettirir ama dikkat dağıtmaz.
  static LinearGradient get background => LinearGradient(
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

  static TextStyle get display => TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get heading => TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );

  static TextStyle get subheading => TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get body => TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.textSecondary,
        fontSize: 14,
        height: 1.45,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.textMuted,
        fontSize: 12,
      );

  // Marka gradyanlı CTA'ların üzerindeki metin - o zemin her palette'te de
  // yeterince koyu/doygun olduğu için bilerek SABİT beyaz (temaya bağlı
  // değil), bu yüzden const kalabiliyor.
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
      decoration: BoxDecoration(gradient: AppGradients.background),
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
            child: _Glow(color: AppColors.secondary.withValues(alpha: 0.10)),
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
  final Gradient? gradient;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 58,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient ?? AppGradients.primary,
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
  }
}

const appPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _AppPageTransitionsBuilder(),
    TargetPlatform.iOS: _AppPageTransitionsBuilder(),
    TargetPlatform.macOS: _AppPageTransitionsBuilder(),
    TargetPlatform.windows: _AppPageTransitionsBuilder(),
    TargetPlatform.linux: _AppPageTransitionsBuilder(),
  },
);

/// Uygulamanın tam ThemeData'sı - main.dart'ta MaterialApp'e verilir. Aktif
/// tema (appThemeNotifier) değiştiğinde main.dart bu fonksiyonu YENİDEN
/// çağırıp MaterialApp'i tazeler (bkz. main.dart'taki ValueListenableBuilder).
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: AppColors.brightness,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: AppColors.brightness,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
    fontFamily: 'Roboto',
    pageTransitionsTheme: appPageTransitionsTheme,
    textTheme: TextTheme(
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
      // Önceden sabit `Colors.white.withValues(alpha: 0.06)` idi - açık
      // temalarda beyaz-üstü-beyaz dolgu neredeyse görünmez olurdu, bu
      // yüzden metin rengine göre (koyu temada beyaz, açık temalarda koyu)
      // ÇOK düşük alfa ile "hafif tonlanmış" bir dolgu üretiyoruz - her iki
      // yönde de görünür ama dikkat çekmeyen bir giriş kutusu.
      fillColor: AppColors.textPrimary.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: AppColors.textFaint),
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
