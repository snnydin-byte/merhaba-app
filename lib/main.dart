import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/call_service.dart';
import 'services/messaging_service.dart';
import 'services/navigation_service.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'utils/text_scale_notifier.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // FlutterError/Zone hataları aşağıda zaten yakalanıyordu ama yalnızca
    // print() ile konsola yazılıyordu - bu, yalnızca bir debug oturumuna
    // bağlıyken görülebilir, gerçek kullanıcının cihazında oluşan bir
    // crash'i asla göremiyorduk. Firebase.initializeApp() PushNotification-
    // Service().init()'in zaten yaptığı işi burada TEKRAR yapıyor gibi
    // görünse de, Crashlytics'in FlutterError.onError içinde kullanılabilmesi
    // için Firebase'in bu callback tanımlanmadan ÖNCE hazır olması gerekiyor
    // - firebase_core zaten idempotent (aynı app'i iki kez başlatmayı
    // sorunsuz görmezden gelir), bu yüzden burada await etmek güvenli.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
    } catch (err) {
      // Firebase yapılandırılmamışsa (bkz. firebase_options.dart) ya da
      // ağ/servis sorunuysa, Crashlytics olmadan devam ediyoruz - kilitlenip
      // uygulamayı hiç açtırmamak, hata raporlamadan mahrum kalmaktan çok
      // daha kötü olurdu.
      // ignore: avoid_print
      print('Crashlytics kurulamadı, hata raporlama devre dışı: $err');
    }
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      // ignore: avoid_print
      print(
          'YAKALANAN HATA (FlutterError): ${details.exception}\n${details.stack}');
      previousOnError?.call(details);
    };
    // Bilerek await EDİLMİYOR - Firebase/push kurulumu splash ekranını
    // geciktirmesin diye arka planda ilerliyor. Firebase henüz
    // yapılandırılmadıysa (bkz. firebase_options.dart) zaten hemen, sessizce
    // döner - bkz. PushNotificationService.init() içindeki açıklama.
    PushNotificationService().init();
    runApp(const MerhabaApp());
  }, (error, stack) {
    // ignore: avoid_print
    print('YAKALANAN HATA (Zone): $error\n$stack');
    // Firebase hiç başlatılamadıysa (yukarıdaki catch) bu çağrı sessizce
    // no-op olur - FirebaseCrashlytics.instance kendi içinde bunu kontrol
    // eder, burada ayrıca bir try/catch'e gerek yok.
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class MerhabaApp extends StatefulWidget {
  const MerhabaApp({super.key});

  @override
  State<MerhabaApp> createState() => _MerhabaAppState();
}

class _MerhabaAppState extends State<MerhabaApp> with WidgetsBindingObserver {
  // "Yapışkan" (sticky) bir zaman damgası - yalnızca son durumla
  // karşılaştırmak YETERLİ DEĞİL, çünkü gerçek arka plana atılma sırası
  // genellikle paused -> inactive -> resumed şeklinde ilerliyor: "inactive"
  // durumu "resumed"dan hemen önce ARAYA GİRİYOR, bu yüzden yalnızca "bir
  // önceki durum"a bakan bir kontrol her zaman "inactive"i görüp arka plana
  // atılmayı KAÇIRIYORDU. Bunun yerine, paused/detached'a her girildiğinde
  // o anın zamanını kaydedip yalnızca gerçekten "resumed" durumuna
  // gelindiğinde tüketiyoruz (sıfırlıyoruz) - araya giren "inactive"
  // durumları bunu ETKİLEMİYOR.
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadTextScalePreference();
    loadAppThemePreference();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt == null) return; // hiç arka plana atılmamıştı (yalnızca "inactive" geçişiydi)
      final backgroundedFor = DateTime.now().difference(backgroundedAt);
      _reconnectPersistentServices(backgroundedFor: backgroundedFor);
    }
  }

  /// Mobil işletim sistemleri (özellikle Android) arka plandaki soket
  /// bağlantılarını kendi bilgisi dışında koparabiliyor - socket.io
  /// istemcisi bunu her zaman hemen fark edemiyor, "bağlı" görünmeye devam
  /// edip aslında "hayalet" kalabiliyor.
  ///
  /// ÖNCEDEN burada, arka plandan HER dönüşte (telefonun kilidini açıp
  /// kapatmak gibi çok sık/sıradan bir hareket dahil) mesajlaşma soketi
  /// KOŞULSUZ olarak tamamen kesilip yeniden kuruluyordu. Bu, sorun
  /// çözmekten çok yeni bir sorun yaratıyordu: bağlantı zaten sapasağlam
  /// olsa bile her seferinde (a) kullanıcıya gereksiz bir "bağlantı
  /// kesildi" mesajı gösteriliyor, (b) sunucu tarafında kısa bir an için
  /// kullanıcı gerçekten "çevrimdışı" görünüyordu (ki tam o anda biri onu
  /// aramaya çalışırsa "karşı taraf çevrimdışı" hatası alınabiliyordu) - bu
  /// da kullanıcıların bildirdiği "sürekli kopuyor" hissinin BİZİM
  /// kendi kodumuzdan kaynaklanan asıl nedeni olabilirdi.
  ///
  /// Artık yalnızca uygulama GERÇEKTEN uzun bir süre (8 saniyeden fazla)
  /// arka planda kaldıysa tam yeniden bağlanıyoruz - kısa geçişlerde
  /// (ör. hızlıca bildirim çubuğuna bakıp dönmek, ekranı kilitleyip hemen
  /// açmak) socket.io'nun kendi ping/pong mekanizmasına güveniyoruz; o
  /// zaten gerçekten ölü bir bağlantıyı en geç ~85 saniyede (pingInterval +
  /// pingTimeout, bkz. server.js) kendiliğinden tespit edip sessizce
  /// yeniden bağlanıyor. Soket zaten kopmuşsa (`isConnected == false`) süre
  /// kısa olsa bile yine de yeniden bağlanıyoruz - bunun hiçbir maliyeti
  /// yok çünkü zaten kopuk.
  ///
  /// Arama bağlantısı için aktif bir görüşme sürüyorsa (bkz.
  /// CallService.isInActiveCall) HİÇBİR ZAMAN zorla kesmiyoruz - aksi
  /// halde devam eden bir görüşme sırasında (ör. kısa süreliğine başka bir
  /// uygulamaya geçilmesi) sinyal soketini koşulsuz kapatıp yeniden açmak,
  /// hâlâ sorunsuz çalışıyor olabilecek görüşmeyi de kesintiye uğratır.
  static const _longBackgroundThreshold = Duration(seconds: 8);

  void _reconnectPersistentServices({required Duration backgroundedFor}) {
    if (!AuthService().isLoggedIn) return;
    final token = AuthService().token;
    if (token == null) return;

    final wasLongBackground = backgroundedFor > _longBackgroundThreshold;

    final messaging = MessagingService();
    if (wasLongBackground || !messaging.isConnected) {
      messaging.reconnect(token);
    }

    final call = CallService();
    if (!call.isInActiveCall && (wasLongBackground || !call.isConnected)) {
      call.reconnect(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tema seçimi (Koyu/Oyunlaştırılmış Enerji/Güven & Berraklık) artık
    // runtime'da değiştirilebiliyor (bkz. app_theme.dart'taki
    // appThemeNotifier) - MaterialApp'i burada sarmalayıp appThemeNotifier
    // her değiştiğinde `theme: buildAppTheme()`'i YENİDEN çağırıyoruz, aksi
    // halde MaterialApp yalnızca ilk açılışta hesaplanmış eski paleti
    // gösterirdi. navigatorKey aynı kaldığı için Navigator'ın mevcut yığını
    // (ör. Ayarlar ekranındayken tema değiştirmek) korunuyor.
    return ValueListenableBuilder<AppThemeVariant>(
      valueListenable: appThemeNotifier,
      builder: (context, _, __) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Merhaba',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          // Yazı boyutu kişiselleştirmesi (Batch G) - bkz. text_scale_notifier
          // .dart'taki kapsam notu. AppColors'a dokunmuyor, yalnızca MediaQuery
          // üzerinden metin ölçeğini değiştiriyor.
          builder: (context, child) {
            return ValueListenableBuilder<double>(
              valueListenable: textScaleNotifier,
              builder: (context, scale, _) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                );
              },
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
