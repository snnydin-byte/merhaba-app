import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Özel/temalı arayüz kişiselleştirmesi (Batch G) - **KAPSAMI BİLİNÇLİ
/// OLARAK DARALTILDI**: tam bir vurgu rengi/tema değişimi, theme/app_theme
/// .dart'taki `AppColors`'ın uygulama genelinde `static const` olarak VE
/// `const` constructor'lar içinde kullanılması nedeniyle runtime'da
/// değiştirilemez (bkz. Batch F'teki "renk körü dostu tema" ertelemesiyle
/// AYNI mimari kısıt). Bunun yerine, AppColors'a HİÇ dokunmayan, gerçek bir
/// erişilebilirlik/kişiselleştirme değeri sunan yazı boyutu ölçeklendirmesi
/// uygulanıyor - MaterialApp'in `builder`ında bir MediaQuery override'ı ile.
///
/// Basit bir ValueNotifier (Provider/Riverpod gibi bir paket eklemeye
/// gerek yok) - main.dart bunu dinler, settings_screen.dart değiştirir.
final ValueNotifier<double> textScaleNotifier = ValueNotifier<double>(1.0);

const String textScalePrefKey = 'text_scale';

Future<void> loadTextScalePreference() async {
  final prefs = await SharedPreferences.getInstance();
  textScaleNotifier.value = prefs.getDouble(textScalePrefKey) ?? 1.0;
}

Future<void> setTextScalePreference(double scale) async {
  textScaleNotifier.value = scale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(textScalePrefKey, scale);
}
