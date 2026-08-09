import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';
import 'notification_preferences_repository.dart';
import 'push_notification_dependencies.dart';
import 'push_notification_platform.dart';
import 'push_interaction_router.dart';
import 'push_token_repository.dart';

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
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
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
  static final PushNotificationService instance =
      PushNotificationService._internal();
  factory PushNotificationService() => instance;

  PushNotificationDependencies _dependencies =
      PushNotificationDependencies.production();
  StreamSubscription<PushNotificationPayload>? _foregroundSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<PushNotificationPayload>? _openedMessageSubscription;
  Future<void> _tokenSyncTail = Future<void>.value();
  bool _initialized = false;
  bool _enabled = true;
  String? _lastRegisteredToken;
  String? _lastRegisteredUserId;
  PushAuthSnapshot _observedAuth = const PushAuthSnapshot();
  bool _authListenerAttached = false;

  PushMessagingPlatform get _messagingPlatform =>
      _dependencies.messagingPlatform;
  LocalNotificationPlatform get _localNotifications =>
      _dependencies.localNotifications;
  NotificationPreferencesRepository get _preferences =>
      _dependencies.preferences;
  PushTokenRepository get _tokenRepository => _dependencies.tokenRepository;
  PushAuthSession get _authSession => _dependencies.authSession;
  bool get _isConfigured => _dependencies.isFirebaseConfigured();

  bool get isEnabled => _enabled;

  void setPreferencesForTesting(NotificationPreferencesRepository preferences) {
    _dependencies = _dependencies.copyWith(preferences: preferences);
  }

  void setTokenRepositoryForTesting(PushTokenRepository repository) {
    _dependencies = _dependencies.copyWith(tokenRepository: repository);
  }

  void setFirebaseConfiguredForTesting(bool Function() isConfigured) {
    _dependencies = _dependencies.copyWith(
      isFirebaseConfigured: isConfigured,
    );
  }

  void setPlatformsForTesting({
    required PushMessagingPlatform messaging,
    required LocalNotificationPlatform localNotifications,
  }) {
    _dependencies = _dependencies.copyWith(
      messagingPlatform: messaging,
      localNotifications: localNotifications,
    );
  }

  void setAuthSessionForTesting(PushAuthSession authSession) {
    _detachAuthListener();
    _dependencies = _dependencies.copyWith(authSession: authSession);
    _observedAuth = authSession.snapshot;
    if (_initialized) _attachAuthListener();
  }

  void setDependenciesForTesting(PushNotificationDependencies dependencies) {
    _detachAuthListener();
    _dependencies = dependencies;
    _observedAuth = dependencies.authSession.snapshot;
    if (_initialized) _attachAuthListener();
  }

  Future<void> resetForTesting() async {
    await _foregroundSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _openedMessageSubscription?.cancel();
    _foregroundSubscription = null;
    _tokenRefreshSubscription = null;
    _openedMessageSubscription = null;
    _initialized = false;
    _enabled = true;
    _detachAuthListener();
    _lastRegisteredToken = null;
    _lastRegisteredUserId = null;
    _observedAuth = const PushAuthSnapshot();
    _tokenSyncTail = Future<void>.value();
    _dependencies = PushNotificationDependencies.production();
  }

  Future<void> init() async {
    if (_initialized || !_isConfigured) {
      if (!_isConfigured) {
        // ignore: avoid_print
        print(
            'Firebase yapılandırılmadı (bkz. lib/firebase_options.dart) - push bildirimleri devre dışı.');
      }
      return;
    }

    _observedAuth = _authSession.snapshot;
    _attachAuthListener();

    try {
      await _messagingPlatform.initialize();
      _messagingPlatform.registerBackgroundHandler(
        firebaseMessagingBackgroundHandler,
      );

      await _localNotifications.initialize();

      _enabled = await _preferences.loadEnabled();

      _foregroundSubscription ??= _messagingPlatform.foregroundMessages
          .listen(_showForegroundNotification);
      _tokenRefreshSubscription ??=
          _messagingPlatform.tokenRefreshes.listen((newToken) {
        if (_enabled) {
          unawaited(_registerToken(newToken));
        }
      });
      _openedMessageSubscription ??=
          _messagingPlatform.openedMessages.listen((payload) {
        unawaited(PushInteractionRouter().handle(payload));
      });

      _initialized = true;

      final initialMessage = await _messagingPlatform.getInitialMessage();
      if (initialMessage != null) {
        unawaited(PushInteractionRouter().handle(initialMessage));
      }

      if (_enabled) {
        await _requestPermissionAndRegister();
      } else {
        await _localNotifications.cancelAll();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Firebase başlatılamadı, push bildirimleri devre dışı: $e');
    }
  }

  Future<void> _requestPermissionAndRegister() async {
    await _messagingPlatform.requestPermission();
    final token = await _messagingPlatform.getToken();
    if (token != null) await _registerToken(token);
  }

  /// Bildirim tercihini kalıcı olarak günceller ve FCM sunucu kaydını aynı
  /// işlemle senkronize eder. Devre dışı bırakıldığında mevcut token hesaptan
  /// ayrılır ve bekleyen yerel bildirimler temizlenir. Yeniden açıldığında
  /// izin durumu kontrol edilip token tekrar kaydedilir.
  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled && _initialized) {
      await _preferences.setEnabled(enabled);
      return;
    }

    final previous = _enabled;
    await _preferences.setEnabled(enabled);
    _enabled = enabled;

    try {
      if (!_initialized) {
        await init();
        return;
      }
      if (enabled) {
        await _requestPermissionAndRegister();
      } else {
        await unregisterCurrentToken();
        await _localNotifications.cancelAll();
      }
    } catch (_) {
      _enabled = previous;
      await _preferences.setEnabled(previous);
      rethrow;
    }
  }

  void _showForegroundNotification(PushNotificationPayload notification) {
    if (!_enabled ||
        (notification.title == null && notification.body == null)) {
      return;
    }
    // flutter_local_notifications v21+ show()'ı da isimli parametreye
    // çevirdi (id hariç hepsi named) - bkz. yukarıdaki initialize() notu.
    unawaited(_localNotifications.show(
      id: notification.id?.hashCode ?? notification.hashCode,
      title: notification.title,
      body: notification.body,
    ));
  }

  /// Kullanıcı giriş yaptıktan sonra (bkz. login_screen.dart, splash_screen.dart)
  /// çağrılır - o an elimizde bir token varsa sunucuya kaydeder. Giriş
  /// yapılmamışsa sessizce hiçbir şey yapmaz; oturumsuz cihaza push
  /// bildirimi gönderilmiyor (kalıcı bir kimlikleri olmadığı için anlamsız).
  Future<void> registerTokenWithServer() async {
    if (!_isConfigured || !_initialized || !_enabled) return;
    final token = await _messagingPlatform.getToken();
    if (token != null) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) return;
    final auth = _authSession.snapshot;
    return _serializeTokenSync(
      () => _registerTokenForSession(normalizedToken, auth),
    );
  }

  Future<void> _registerTokenForSession(
    String normalizedToken,
    PushAuthSnapshot auth,
  ) async {
    if (!_enabled || !auth.isLoggedIn) return;
    if (_lastRegisteredToken == normalizedToken &&
        _lastRegisteredUserId == auth.userId) {
      return;
    }
    try {
      await _tokenRepository.register(
        authToken: auth.token!,
        deviceToken: normalizedToken,
        platform: _messagingPlatform.serverPlatform,
      );
      _lastRegisteredToken = normalizedToken;
      _lastRegisteredUserId = auth.userId;
    } catch (e) {
      // Sunucuya ulaşılamıyor - önemli değil, bir sonraki fırsatta
      // tekrar denenecek.
      // ignore: avoid_print
      print('Push token sunucuya kaydedilemedi: $e');
    }
  }

  void _attachAuthListener() {
    if (_authListenerAttached) return;
    _authSession.addListener(_handleAuthSessionChanged);
    _authListenerAttached = true;
  }

  void _detachAuthListener() {
    if (!_authListenerAttached) return;
    _authSession.removeListener(_handleAuthSessionChanged);
    _authListenerAttached = false;
  }

  void _handleAuthSessionChanged() {
    final previous = _observedAuth;
    final next = _authSession.snapshot;
    if (previous == next) return;
    _observedAuth = next;

    if (!_initialized || !_isConfigured) return;
    unawaited(_serializeTokenSync(() async {
      final deviceToken = (await _messagingPlatform.getToken())?.trim();
      if (deviceToken == null || deviceToken.isEmpty) return;

      final accountChanged = previous.userId != next.userId;
      final credentialChanged = previous.token != next.token;
      if (previous.isLoggedIn && (accountChanged || credentialChanged)) {
        await _unregisterTokenForSession(deviceToken, previous);
      }
      if (_enabled && next.isLoggedIn) {
        await _registerTokenForSession(deviceToken, next);
      }
    }));
  }

  Future<void> _unregisterTokenForSession(
    String deviceToken,
    PushAuthSnapshot auth,
  ) async {
    if (!auth.isLoggedIn) return;
    try {
      await _tokenRepository.unregister(
        authToken: auth.token!,
        deviceToken: deviceToken,
      );
    } catch (_) {
      // Çıkış ve hesap değişimi token temizliği ağ hatası yüzünden
      // engellenmemeli. Sunucu tarafında geçersiz tokenlar ayrıca temizlenir.
    } finally {
      if (_lastRegisteredUserId == auth.userId) {
        _lastRegisteredToken = null;
        _lastRegisteredUserId = null;
      }
    }
  }

  Future<void> _serializeTokenSync(Future<void> Function() operation) {
    final current = _tokenSyncTail.then((_) => operation());
    _tokenSyncTail = current.catchError((_) {
      // Bir kayıt/silme hatası sonraki token işlemlerini bloke etmemeli.
    });
    return current;
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
  void showLocalMessageNotification(
      {required String title, required String body}) {
    if (!_initialized || !_enabled) return;
    unawaited(_localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
    ));
  }

  /// Çıkış yapılırken çağrılır (bkz. profile_screen.dart _logout()) - bu
  /// cihazın token'ını hesaptan ayırır, böylece çıkış sonrası o hesaba
  /// artık bu cihaza push gönderilmeye çalışılmaz. Başarısız olursa
  /// (sunucuya ulaşılamıyor vb.) sessizce yok sayılır - çıkış işlemini
  /// engellememeli.
  Future<void> unregisterCurrentToken() async {
    if (!_isConfigured || !_initialized) return;
    final auth = _authSession.snapshot;
    return _serializeTokenSync(() async {
      final token = (await _messagingPlatform.getToken())?.trim();
      if (token == null || token.isEmpty) return;
      await _unregisterTokenForSession(token, auth);
    });
  }
}
