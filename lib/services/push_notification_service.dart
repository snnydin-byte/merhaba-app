import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'auth_service.dart';
import 'webrtc_service.dart' show signalingServerUrl;

const String _messagesChannelId = 'merhaba_messages';

/// Uygulama arka plandayken/tamamen kapalıyken gelen FCM mesajlarını işler.
/// Dart'ın izole (isolate) arka plan yürütme modeli gereği bu fonksiyon
/// TOP-LEVEL (sınıf dışı) olmalı ve @pragma('vm:entry-point') ile
/// işaretlenmeli - aksi halde release modda derleyici bunu "kullanılmıyor"
/// sanıp silebilir. main.dart'ta FirebaseMessaging.onBackgroundMessage()
/// ile kaydedilir.
///
/// Bu izole kendi başına çalıştığı için (ana uygulama state'ine erişimi
/// yok) burada Firebase'i YENİDEN başlatmamız gerekiyor - init() içindeki
/// mantığın küçük bir alt kümesi.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!isFirebaseConfigured) return;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Zaten başlatılmış olabilir (aynı izole başka bir mesajı da işlemiş
    // olabilir) - bu durumda initializeApp ikinci kez çağrılınca hata
    // fırlatır, yok sayıyoruz.
  }
  // Bildirim (notification) alanı olan mesajlar sistem tarafından OTOMATİK
  // gösterilir (Android/iOS bunu FCM SDK seviyesinde yapar) - burada ekstra
  // bir şey yapmamıza gerek yok, sadece isteğe bağlı loglama için buradayız.
  // ignore: avoid_print
  print('Arka planda push bildirimi alındı: ${message.messageId}');
}

/// Firebase Cloud Messaging entegrasyonunu yönetir: izin ister, cihaz
/// token'ını alır ve sunucuya kaydeder (bkz. server.js POST /push-token),
/// ön plandayken gelen mesajları flutter_local_notifications ile sistem
/// bildirimi olarak gösterir (FCM bunu ön plandayken OTOMATİK yapmaz - bu
/// iyi bilinen bir platform kısıtlaması).
///
/// GERÇEK bir Firebase projesi yapılandırılana kadar (bkz.
/// firebase_options.dart'taki isFirebaseConfigured) init() sessizce hiçbir
/// şey yapmadan döner - uygulamanın geri kalanı bundan habersiz, normal
/// çalışmaya devam eder (TURN sunucusu yapılandırılmadığında STUN'a
/// düşülmesiyle aynı "zarif geri düşme" deseni, bkz. webrtc_service.dart).
class PushNotificationService {
  PushNotificationService._internal();
  static final PushNotificationService instance = PushNotificationService._internal();
  factory PushNotificationService() => instance;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastRegisteredToken;

  Future<void> init() async {
    if (_initialized || !isFirebaseConfigured) {
      if (!isFirebaseConfigured) {
        // ignore: avoid_print
        print('Firebase yapılandırılmadı (bkz. lib/firebase_options.dart) - push bildirimleri devre dışı.');
      }
      return;
    }

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _setupLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      // iOS'ta bu bir sistem izin diyaloğu açar; Android 13+'ta ise
      // firebase_messaging otomatik olarak POST_NOTIFICATIONS çalışma
      // zamanı iznini ister (manifest'te tanımlı olması yeterli, bkz.
      // AndroidManifest.xml).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      messaging.onTokenRefresh.listen((newToken) {
        _lastRegisteredToken = null; // token değişti, tekrar kaydedilmeli
        _registerToken(newToken);
      });

      _initialized = true;

      final token = await messaging.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      // ignore: avoid_print
      print('Firebase başlatılamadı, push bildirimleri devre dışı: $e');
    }
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    // flutter_local_notifications v21+ initialize()'ı isimli (named)
    // parametreye çevirdi (eskiden ilk parametre pozisyoneldi) - bkz.
    // https://pub.dev/documentation/flutter_local_notifications/latest/
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _messagesChannelId,
        'Mesajlar ve bildirimler',
        description: 'Yeni mesaj ve arkadaşlık bildirimleri',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    // flutter_local_notifications v21+ show()'ı da isimli parametreye
    // çevirdi (id hariç hepsi named) - bkz. yukarıdaki initialize() notu.
    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _messagesChannelId,
          'Mesajlar ve bildirimler',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Kullanıcı giriş yaptıktan sonra (bkz. login_screen.dart, splash_screen.dart)
  /// çağrılır - o an elimizde bir token varsa sunucuya kaydeder. Giriş
  /// yapılmamışsa (misafir) sessizce hiçbir şey yapmaz; misafirlere push
  /// bildirimi gönderilmiyor (kalıcı bir kimlikleri olmadığı için anlamsız).
  Future<void> registerTokenWithServer() async {
    if (!isFirebaseConfigured || !_initialized) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    if (!AuthService().isLoggedIn) return;
    if (_lastRegisteredToken == token) return; // zaten kayıtlı, tekrar istek atma
    final authToken = AuthService().token;
    if (authToken == null) return;
    try {
      final response = await http
          .post(
            Uri.parse('$signalingServerUrl/push-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastRegisteredToken = token;
      }
    } catch (e) {
      // Sunucuya ulaşılamıyor - önemli değil, bir sonraki fırsatta
      // (uygulama yeniden açıldığında ya da token yenilendiğinde) tekrar
      // denenecek.
      // ignore: avoid_print
      print('Push token sunucuya kaydedilemedi: $e');
    }
  }

  /// Anlık (ön plan) bir olay için yerel bildirim gösterir - FCM push'tan
  /// bağımsız olarak. Mesajlaşma/arama servisleri, kullanıcı ilgili sohbet
  /// ekranında DEĞİLKEN gelen bir mesajı ona bildirmek için bunu çağırır
  /// (bkz. messaging_service.dart). Sunucu tarafı zaten yalnızca kullanıcı
  /// hiçbir socket'e bağlı değilken FCM push gönderiyor (bkz. server.js
  /// isUserOnline kontrolü) - artık mesajlaşma bağlantısı kalıcı olduğu için
  /// (bkz. messaging_service.dart) kullanıcı neredeyse her zaman "çevrimiçi"
  /// sayılacak ve o push hiç tetiklenmeyecek; ekranda değilken haberdar
  /// olabilmesi için bu yerel bildirim yolu gerekli.
  ///
  /// Firebase/yerel bildirimler hazır değilse (bkz. init()) sessizce hiçbir
  /// şey yapmaz - aynı "zarif geri düşme" deseni.
  void showLocalMessageNotification({required String title, required String body}) {
    if (!_initialized) return;
    _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _messagesChannelId,
          'Mesajlar ve bildirimler',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Çıkış yapılırken çağrılır (bkz. profile_screen.dart _logout()) - bu
  /// cihazın token'ını hesaptan ayırır, böylece çıkış sonrası o hesaba
  /// artık bu cihaza push gönderilmeye çalışılmaz. Başarısız olursa
  /// (sunucuya ulaşılamıyor vb.) sessizce yok sayılır - çıkış işlemini
  /// engellememeli.
  Future<void> unregisterCurrentToken() async {
    if (!isFirebaseConfigured || !_initialized) return;
    final authToken = AuthService().token;
    if (authToken == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await http
          .delete(
            Uri.parse('$signalingServerUrl/push-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // önemli değil, bkz. yukarıdaki not
    } finally {
      _lastRegisteredToken = null;
    }
  }
}
