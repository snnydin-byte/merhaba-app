import 'package:flutter/foundation.dart';

import '../firebase_options.dart' as firebase_options;
import 'auth_service.dart';
import 'notification_preferences_repository.dart';
import 'push_notification_platform.dart';
import 'push_token_repository.dart';
import 'webrtc_service.dart' show signalingServerUrl;

@immutable
class PushAuthSnapshot {
  const PushAuthSnapshot({this.token, this.userId});

  final String? token;
  final String? userId;

  bool get isLoggedIn => token != null && userId != null;

  @override
  bool operator ==(Object other) =>
      other is PushAuthSnapshot &&
      other.token == token &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(token, userId);
}

abstract class PushAuthSession {
  PushAuthSnapshot get snapshot;
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
}

class AuthServicePushAuthSession implements PushAuthSession {
  const AuthServicePushAuthSession();

  @override
  PushAuthSnapshot get snapshot {
    final state = AuthService().sessionState.value;
    return PushAuthSnapshot(token: state.token, userId: state.user?.id);
  }

  @override
  void addListener(VoidCallback listener) {
    AuthService().sessionState.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    AuthService().sessionState.removeListener(listener);
  }
}

class PushNotificationDependencies {
  const PushNotificationDependencies({
    required this.messagingPlatform,
    required this.localNotifications,
    required this.preferences,
    required this.tokenRepository,
    required this.authSession,
    required this.isFirebaseConfigured,
  });

  factory PushNotificationDependencies.production() {
    return PushNotificationDependencies(
      messagingPlatform: FirebasePushMessagingPlatform(),
      localNotifications: FlutterLocalNotificationPlatform(),
      preferences: NotificationPreferencesRepository(),
      tokenRepository: PushTokenRepository(baseUrl: signalingServerUrl),
      authSession: const AuthServicePushAuthSession(),
      isFirebaseConfigured: () => firebase_options.isFirebaseConfigured,
    );
  }

  final PushMessagingPlatform messagingPlatform;
  final LocalNotificationPlatform localNotifications;
  final NotificationPreferencesRepository preferences;
  final PushTokenRepository tokenRepository;
  final PushAuthSession authSession;
  final bool Function() isFirebaseConfigured;

  PushNotificationDependencies copyWith({
    PushMessagingPlatform? messagingPlatform,
    LocalNotificationPlatform? localNotifications,
    NotificationPreferencesRepository? preferences,
    PushTokenRepository? tokenRepository,
    PushAuthSession? authSession,
    bool Function()? isFirebaseConfigured,
  }) {
    return PushNotificationDependencies(
      messagingPlatform: messagingPlatform ?? this.messagingPlatform,
      localNotifications: localNotifications ?? this.localNotifications,
      preferences: preferences ?? this.preferences,
      tokenRepository: tokenRepository ?? this.tokenRepository,
      authSession: authSession ?? this.authSession,
      isFirebaseConfigured: isFirebaseConfigured ?? this.isFirebaseConfigured,
    );
  }
}
