import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'call_service.dart';
import 'call_ui_controller.dart';
import 'connection_retry_controller.dart';
import 'messaging_service.dart';
import 'app_connection_state.dart';

/// Kalıcı Socket.IO bağlantılarını kullanıcı oturumuyla eşzamanlı tutar.
///
/// Ekranlar artık bağlantı açıp kapatmaz. Oturum açıldığında mesajlaşma ve
/// arama socketleri doğru JWT ile kurulur; çıkışta veya hesap değişiminde
/// eski hesaba ait bağlantılar önce tamamen kapatılır.
class SocketSessionCoordinator {
  SocketSessionCoordinator._internal()
      : _dependencies = SocketSessionDependencies.production();

  static final SocketSessionCoordinator instance =
      SocketSessionCoordinator._internal();

  factory SocketSessionCoordinator() => instance;

  SocketSessionDependencies _dependencies;
  bool _initialized = false;
  String? _activeToken;
  late final ConnectionRetryAction _messagingRetryAction =
      CallbackConnectionRetryAction(() {
    final token = _activeToken;
    if (token != null) _dependencies.messaging.reconnect(token);
  });
  late final ConnectionRetryAction _callRetryAction =
      CallbackConnectionRetryAction(() {
    final token = _activeToken;
    if (token != null && !_dependencies.call.isInActiveCall) {
      _dependencies.call.reconnect(token);
    }
  });

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _dependencies.authSession.addListener(_handleSessionChanged);
    ConnectionRetryController()
      ..register(AppConnectionChannel.messaging, _messagingRetryAction)
      ..register(AppConnectionChannel.call, _callRetryAction);
    _synchronize(_dependencies.authSession.value);
  }

  void _handleSessionChanged() {
    _synchronize(_dependencies.authSession.value);
  }

  void _synchronize(AuthSessionState session) {
    final nextToken = session.isAuthenticated ? session.token : null;
    if (nextToken == _activeToken) return;

    final callWasActive = _dependencies.call.isInActiveCall;
    if (_activeToken != null) {
      _dependencies.messaging.disconnect();
      // Access token yenilenmesi devam eden bir WebRTC görüşmesini kesmemeli.
      // Aktif call socket'i mevcut handshake yetkisiyle görüşme sonuna kadar
      // kalır; sonraki bağlantıda yeni token kullanılır.
      if (!callWasActive) _dependencies.call.disconnect();
    }

    _activeToken = nextToken;
    if (nextToken == null) return;

    _dependencies.callUi.wire();
    _dependencies.messaging.connect(nextToken);
    if (!callWasActive) _dependencies.call.connect(nextToken);
  }

  /// Uygulama arka plandan döndüğünde mevcut oturumun socketlerini tazeler.
  /// Aktif görüşme sırasında arama socketi bilerek korunur.
  void reconnectPersistentServices({
    bool reconnectMessaging = true,
    bool reconnectCall = true,
  }) {
    final token = _activeToken;
    if (token == null) return;
    if (reconnectMessaging) {
      _dependencies.messaging.reconnect(token);
    }
    if (reconnectCall && !_dependencies.call.isInActiveCall) {
      _dependencies.call.reconnect(token);
    }
  }

  @visibleForTesting
  void setDependenciesForTesting(SocketSessionDependencies dependencies) {
    if (_initialized) {
      _dependencies.authSession.removeListener(_handleSessionChanged);
      ConnectionRetryController()
        ..unregister(AppConnectionChannel.messaging, _messagingRetryAction)
        ..unregister(AppConnectionChannel.call, _callRetryAction);
    }
    _dependencies = dependencies;
    _initialized = false;
    _activeToken = null;
  }

  @visibleForTesting
  void resetForTesting() {
    if (_initialized) {
      _dependencies.authSession.removeListener(_handleSessionChanged);
      ConnectionRetryController()
        ..unregister(AppConnectionChannel.messaging, _messagingRetryAction)
        ..unregister(AppConnectionChannel.call, _callRetryAction);
    }
    _dependencies.messaging.disconnect();
    _dependencies.call.disconnect();
    _dependencies = SocketSessionDependencies.production();
    _initialized = false;
    _activeToken = null;
  }
}

abstract class SocketAuthSession {
  AuthSessionState get value;
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
}

class AuthServiceSocketAuthSession implements SocketAuthSession {
  const AuthServiceSocketAuthSession();

  @override
  AuthSessionState get value => AuthService().sessionState.value;

  @override
  void addListener(VoidCallback listener) {
    AuthService().sessionState.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    AuthService().sessionState.removeListener(listener);
  }
}

abstract class PersistentSocketClient {
  void connect(String token);
  void reconnect(String token);
  void disconnect();
}

class MessagingSocketClient implements PersistentSocketClient {
  const MessagingSocketClient();

  @override
  void connect(String token) => MessagingService().connectIfNeeded(token);

  @override
  void reconnect(String token) => MessagingService().reconnect(token);

  @override
  void disconnect() => MessagingService().disconnectSocket();
}

abstract class PersistentCallSocketClient implements PersistentSocketClient {
  bool get isInActiveCall;
}

class CallSocketClient implements PersistentCallSocketClient {
  const CallSocketClient();

  @override
  bool get isInActiveCall => CallService().isInActiveCall;

  @override
  void connect(String token) => CallService().connectIfNeeded(token);

  @override
  void reconnect(String token) => CallService().reconnect(token);

  @override
  void disconnect() => CallService().disconnectSocket();
}

abstract class CallUiBinding {
  void wire();
}

class DefaultCallUiBinding implements CallUiBinding {
  const DefaultCallUiBinding();

  @override
  void wire() => CallUiController().wire();
}

class SocketSessionDependencies {
  const SocketSessionDependencies({
    required this.authSession,
    required this.messaging,
    required this.call,
    required this.callUi,
  });

  factory SocketSessionDependencies.production() {
    return const SocketSessionDependencies(
      authSession: AuthServiceSocketAuthSession(),
      messaging: MessagingSocketClient(),
      call: CallSocketClient(),
      callUi: DefaultCallUiBinding(),
    );
  }

  final SocketAuthSession authSession;
  final PersistentSocketClient messaging;
  final PersistentCallSocketClient call;
  final CallUiBinding callUi;
}
