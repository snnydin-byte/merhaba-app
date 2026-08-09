import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

const String messagesNotificationChannelId = 'merhaba_messages';

class PushNotificationPayload {
  const PushNotificationPayload({
    this.id,
    this.title,
    this.body,
    this.data = const <String, String>{},
  });

  final String? id;
  final String? title;
  final String? body;
  final Map<String, String> data;
}

Map<String, String> _stringData(Map<String, dynamic> input) =>
    input.map((key, value) => MapEntry(key, value.toString()));

abstract class PushMessagingPlatform {
  Future<void> initialize();
  void registerBackgroundHandler(
    Future<void> Function(RemoteMessage message) handler,
  );
  Stream<PushNotificationPayload> get foregroundMessages;
  Stream<String> get tokenRefreshes;
  Stream<PushNotificationPayload> get openedMessages;
  Future<PushNotificationPayload?> getInitialMessage();
  Future<void> requestPermission();
  Future<String?> getToken();
  String get serverPlatform;
}

class FirebasePushMessagingPlatform implements PushMessagingPlatform {
  FirebasePushMessagingPlatform({FirebaseMessaging? messaging})
      : _messaging = messaging;

  FirebaseMessaging? _messaging;

  FirebaseMessaging get _instance => _messaging ??= FirebaseMessaging.instance;

  @override
  Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  void registerBackgroundHandler(
    Future<void> Function(RemoteMessage message) handler,
  ) {
    FirebaseMessaging.onBackgroundMessage(handler);
  }

  @override
  Stream<PushNotificationPayload> get foregroundMessages =>
      FirebaseMessaging.onMessage.map(
        (message) => PushNotificationPayload(
          id: message.messageId,
          title: message.notification?.title,
          body: message.notification?.body,
          data: _stringData(message.data),
        ),
      );

  @override
  Stream<String> get tokenRefreshes => _instance.onTokenRefresh;

  @override
  Stream<PushNotificationPayload> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map(
        (message) => PushNotificationPayload(
          id: message.messageId,
          title: message.notification?.title,
          body: message.notification?.body,
          data: _stringData(message.data),
        ),
      );

  @override
  Future<PushNotificationPayload?> getInitialMessage() async {
    final message = await _instance.getInitialMessage();
    if (message == null) return null;
    return PushNotificationPayload(
      id: message.messageId,
      title: message.notification?.title,
      body: message.notification?.body,
      data: _stringData(message.data),
    );
  }

  @override
  Future<void> requestPermission() async {
    await _instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  @override
  Future<String?> getToken() => _instance.getToken();

  @override
  String get serverPlatform => Platform.isIOS ? 'ios' : 'android';
}

abstract class LocalNotificationPlatform {
  Future<void> initialize();
  Future<void> cancelAll();
  Future<void> show({
    required int id,
    String? title,
    String? body,
  });
}

class FlutterLocalNotificationPlatform implements LocalNotificationPlatform {
  FlutterLocalNotificationPlatform({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        messagesNotificationChannelId,
        'Mesajlar ve bildirimler',
        description: 'Yeni mesaj ve arkadaşlık bildirimleri',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          messagesNotificationChannelId,
          'Mesajlar ve bildirimler',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
