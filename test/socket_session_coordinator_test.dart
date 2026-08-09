import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/auth_session_state.dart';
import 'package:merhaba_app/services/socket_session_coordinator.dart';
import 'package:merhaba_app/models/app_user.dart';

void main() {
  test('giriş, hesap değişimi ve çıkış socket yaşam döngüsünü yönetir', () {
    final auth = _FakeAuthSession();
    final messaging = _FakeSocketClient();
    final call = _FakeCallSocketClient();
    final callUi = _FakeCallUi();
    final coordinator = SocketSessionCoordinator();
    coordinator.setDependenciesForTesting(SocketSessionDependencies(
      authSession: auth,
      messaging: messaging,
      call: call,
      callUi: callUi,
    ));
    coordinator.initialize();

    auth.set(_session('token-a', 'user-a'));
    expect(messaging.connectedTokens, ['token-a']);
    expect(call.connectedTokens, ['token-a']);
    expect(callUi.wireCount, 1);

    auth.set(_session('token-b', 'user-b'));
    expect(messaging.disconnectCount, 1);
    expect(call.disconnectCount, 1);
    expect(messaging.connectedTokens, ['token-a', 'token-b']);
    expect(call.connectedTokens, ['token-a', 'token-b']);

    auth.set(const AuthSessionState.signedOut());
    expect(messaging.disconnectCount, 2);
    expect(call.disconnectCount, 2);
  });

  test('aynı token tekrar yayınlanırsa bağlantı çoğaltılmaz', () {
    final auth = _FakeAuthSession();
    final messaging = _FakeSocketClient();
    final call = _FakeCallSocketClient();
    final coordinator = SocketSessionCoordinator();
    coordinator.setDependenciesForTesting(SocketSessionDependencies(
      authSession: auth,
      messaging: messaging,
      call: call,
      callUi: _FakeCallUi(),
    ));
    coordinator.initialize();

    final session = _session('same-token', 'user-a');
    auth.set(session);
    auth.set(session);

    expect(messaging.connectedTokens, ['same-token']);
    expect(call.connectedTokens, ['same-token']);
  });
}

AuthSessionState _session(String token, String userId) =>
    AuthSessionState.authenticated(
      token: token,
      user: AppUser(
          id: userId, email: '$userId@example.com', displayName: userId),
    );

class _FakeAuthSession implements SocketAuthSession {
  AuthSessionState _value = const AuthSessionState.signedOut();
  final List<void Function()> _listeners = [];

  @override
  AuthSessionState get value => _value;

  void set(AuthSessionState value) {
    _value = value;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);
}

class _FakeSocketClient implements PersistentSocketClient {
  final List<String> connectedTokens = [];
  final List<String> reconnectedTokens = [];
  int disconnectCount = 0;

  @override
  void connect(String token) => connectedTokens.add(token);

  @override
  void reconnect(String token) => reconnectedTokens.add(token);

  @override
  void disconnect() => disconnectCount++;
}

class _FakeCallSocketClient extends _FakeSocketClient
    implements PersistentCallSocketClient {
  @override
  bool isInActiveCall = false;
}

class _FakeCallUi implements CallUiBinding {
  int wireCount = 0;

  @override
  void wire() => wireCount++;
}
