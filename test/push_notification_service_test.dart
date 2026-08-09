import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/notification_preferences_repository.dart';
import 'package:merhaba_app/services/push_notification_dependencies.dart';
import 'package:merhaba_app/services/push_notification_platform.dart';
import 'package:merhaba_app/services/push_notification_service.dart';
import 'package:merhaba_app/services/push_token_repository.dart';

class _MemoryPreferenceStore implements NotificationPreferencesStore {
  _MemoryPreferenceStore(this.value);

  bool? value;

  @override
  Future<bool?> readEnabled() async => value;

  @override
  Future<void> writeEnabled(bool enabled) async {
    value = enabled;
  }
}

class _FakeMessagingPlatform implements PushMessagingPlatform {
  final foregroundController =
      StreamController<PushNotificationPayload>.broadcast();
  final tokenController = StreamController<String>.broadcast();
  final openedController =
      StreamController<PushNotificationPayload>.broadcast();
  PushNotificationPayload? initialMessage;

  bool initialized = false;
  bool backgroundRegistered = false;
  int permissionRequests = 0;
  int tokenReads = 0;
  String? token = 'test-device-token-abcdefghijklmnopqrstuvwxyz';

  @override
  Stream<PushNotificationPayload> get foregroundMessages =>
      foregroundController.stream;

  @override
  Stream<String> get tokenRefreshes => tokenController.stream;

  @override
  Stream<PushNotificationPayload> get openedMessages => openedController.stream;

  @override
  Future<PushNotificationPayload?> getInitialMessage() async => initialMessage;

  @override
  Future<String?> getToken() async {
    tokenReads++;
    return token;
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  void registerBackgroundHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) {
    backgroundRegistered = true;
  }

  @override
  Future<void> requestPermission() async {
    permissionRequests++;
  }

  @override
  String get serverPlatform => 'android';

  Future<void> close() async {
    await foregroundController.close();
    await tokenController.close();
    await openedController.close();
  }
}

class _FakeAuthSession extends ChangeNotifier implements PushAuthSession {
  _FakeAuthSession(
      {String? authToken = 'auth-token', String? userId = 'user-1'})
      : _snapshot = PushAuthSnapshot(token: authToken, userId: userId);

  PushAuthSnapshot _snapshot;

  @override
  PushAuthSnapshot get snapshot => _snapshot;

  void setSession({String? authToken, String? userId}) {
    _snapshot = PushAuthSnapshot(token: authToken, userId: userId);
    notifyListeners();
  }
}

class _FakePushTokenRepository extends PushTokenRepository {
  _FakePushTokenRepository({this.delay = Duration.zero})
      : super(baseUrl: 'https://example.invalid');

  final Duration delay;
  int registerCount = 0;
  int unregisterCount = 0;
  final registeredTokens = <String>[];
  final registeredAuthTokens = <String>[];
  final unregisteredAuthTokens = <String>[];

  @override
  Future<void> register({
    required String authToken,
    required String deviceToken,
    required String platform,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    registerCount++;
    registeredTokens.add(deviceToken);
    registeredAuthTokens.add(authToken);
    if (delay != Duration.zero) await Future<void>.delayed(delay);
  }

  @override
  Future<void> unregister({
    required String authToken,
    required String deviceToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    unregisterCount++;
    unregisteredAuthTokens.add(authToken);
    if (delay != Duration.zero) await Future<void>.delayed(delay);
  }
}

class _FakeLocalNotifications implements LocalNotificationPlatform {
  bool initialized = false;
  int cancelCount = 0;
  final shown = <PushNotificationPayload>[];

  @override
  Future<void> cancelAll() async {
    cancelCount++;
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
  }) async {
    shown.add(PushNotificationPayload(id: '$id', title: title, body: body));
  }
}

void main() {
  final service = PushNotificationService();
  late _FakeMessagingPlatform messaging;
  late _FakeLocalNotifications local;

  setUp(() async {
    await service.resetForTesting();
    messaging = _FakeMessagingPlatform();
    local = _FakeLocalNotifications();
    service.setFirebaseConfiguredForTesting(() => true);
    service.setPlatformsForTesting(
      messaging: messaging,
      localNotifications: local,
    );
  });

  tearDown(() async {
    await service.resetForTesting();
    await messaging.close();
  });

  test('etkin tercih izin ister ve platformları başlatır', () async {
    service.setPreferencesForTesting(
      NotificationPreferencesRepository(
        store: _MemoryPreferenceStore(true),
      ),
    );

    await service.init();

    expect(messaging.initialized, isTrue);
    expect(messaging.backgroundRegistered, isTrue);
    expect(messaging.permissionRequests, 1);
    expect(messaging.tokenReads, 1);
    expect(local.initialized, isTrue);
    expect(service.isEnabled, isTrue);
  });

  test('kapalı tercih izin istemez ve yerel bildirimleri temizler', () async {
    service.setPreferencesForTesting(
      NotificationPreferencesRepository(
        store: _MemoryPreferenceStore(false),
      ),
    );

    await service.init();

    expect(messaging.permissionRequests, 0);
    expect(messaging.tokenReads, 0);
    expect(local.cancelCount, 1);
    expect(service.isEnabled, isFalse);
  });

  test('ön plan mesajı yalnızca bildirimler etkinken gösterilir', () async {
    final store = _MemoryPreferenceStore(true);
    service.setPreferencesForTesting(
      NotificationPreferencesRepository(store: store),
    );
    await service.init();

    messaging.foregroundController.add(
      const PushNotificationPayload(title: 'Merhaba', body: 'Yeni mesaj'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(local.shown, hasLength(1));

    await service.setEnabled(false);
    messaging.foregroundController.add(
      const PushNotificationPayload(title: 'Gizli', body: 'Gösterilmemeli'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(local.shown, hasLength(1));
    expect(local.cancelCount, greaterThanOrEqualTo(1));
    expect(store.value, isFalse);
  });

  test('aynı token için eşzamanlı kayıt isteği tek ağ çağrısına iner',
      () async {
    final repository = _FakePushTokenRepository(
      delay: const Duration(milliseconds: 10),
    );
    service.setPreferencesForTesting(
      NotificationPreferencesRepository(
        store: _MemoryPreferenceStore(true),
      ),
    );
    service.setTokenRepositoryForTesting(repository);
    service.setAuthSessionForTesting(_FakeAuthSession());

    await service.init();
    expect(repository.registerCount, 1);

    await Future.wait([
      service.registerTokenWithServer(),
      service.registerTokenWithServer(),
      service.registerTokenWithServer(),
    ]);

    expect(repository.registerCount, 1);
  });

  test('token yenilemeleri sırayla kaydedilir ve son token korunur', () async {
    final repository = _FakePushTokenRepository(
      delay: const Duration(milliseconds: 5),
    );
    service.setPreferencesForTesting(
      NotificationPreferencesRepository(
        store: _MemoryPreferenceStore(true),
      ),
    );
    service.setTokenRepositoryForTesting(repository);
    service.setAuthSessionForTesting(_FakeAuthSession());
    await service.init();

    messaging.tokenController.add('refreshed-device-token-111111111111');
    messaging.tokenController.add('refreshed-device-token-222222222222');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(
      repository.registeredTokens,
      containsAllInOrder([
        'test-device-token-abcdefghijklmnopqrstuvwxyz',
        'refreshed-device-token-111111111111',
        'refreshed-device-token-222222222222',
      ]),
    );
  });

  test('bağımlılık kapsayıcısı tek seferde kurulabilir', () async {
    final repository = _FakePushTokenRepository();
    final preferences = NotificationPreferencesRepository(
      store: _MemoryPreferenceStore(false),
    );
    service.setDependenciesForTesting(
      PushNotificationDependencies(
        messagingPlatform: messaging,
        localNotifications: local,
        preferences: preferences,
        tokenRepository: repository,
        authSession: _FakeAuthSession(),
        isFirebaseConfigured: () => true,
      ),
    );

    await service.init();

    expect(service.isEnabled, isFalse);
    expect(repository.registerCount, 0);
    expect(local.cancelCount, 1);
  });

  test('girişte token otomatik olarak yeni hesaba kaydedilir', () async {
    final repository = _FakePushTokenRepository();
    final auth = _FakeAuthSession(authToken: null, userId: null);
    service.setDependenciesForTesting(
      PushNotificationDependencies(
        messagingPlatform: messaging,
        localNotifications: local,
        preferences: NotificationPreferencesRepository(
          store: _MemoryPreferenceStore(true),
        ),
        tokenRepository: repository,
        authSession: auth,
        isFirebaseConfigured: () => true,
      ),
    );
    await service.init();
    expect(repository.registerCount, 0);

    auth.setSession(authToken: 'account-a-token', userId: 'account-a');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.registeredAuthTokens, ['account-a-token']);
  });

  test('çıkışta eski hesap token ilişkisi eski bearer ile silinir', () async {
    final repository = _FakePushTokenRepository();
    final auth = _FakeAuthSession(
      authToken: 'account-a-token',
      userId: 'account-a',
    );
    service.setDependenciesForTesting(
      PushNotificationDependencies(
        messagingPlatform: messaging,
        localNotifications: local,
        preferences: NotificationPreferencesRepository(
          store: _MemoryPreferenceStore(true),
        ),
        tokenRepository: repository,
        authSession: auth,
        isFirebaseConfigured: () => true,
      ),
    );
    await service.init();

    auth.setSession(authToken: null, userId: null);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.unregisteredAuthTokens, ['account-a-token']);
  });

  test('hesap değişiminde önce eski kayıt silinir sonra yeni hesap kaydedilir',
      () async {
    final repository = _FakePushTokenRepository();
    final auth = _FakeAuthSession(
      authToken: 'account-a-token',
      userId: 'account-a',
    );
    service.setDependenciesForTesting(
      PushNotificationDependencies(
        messagingPlatform: messaging,
        localNotifications: local,
        preferences: NotificationPreferencesRepository(
          store: _MemoryPreferenceStore(true),
        ),
        tokenRepository: repository,
        authSession: auth,
        isFirebaseConfigured: () => true,
      ),
    );
    await service.init();

    auth.setSession(authToken: 'account-b-token', userId: 'account-b');
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(repository.unregisteredAuthTokens, ['account-a-token']);
    expect(
      repository.registeredAuthTokens,
      ['account-a-token', 'account-b-token'],
    );
  });
}
