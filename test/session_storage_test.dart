import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merhaba_app/services/auth_api_client.dart';
import 'package:merhaba_app/services/auth_dependencies.dart';
import 'package:merhaba_app/services/auth_service.dart';
import 'package:merhaba_app/services/google_auth_provider.dart';
import 'package:merhaba_app/services/session_storage.dart';

class MemorySessionStorage implements SessionStorage {
  StoredSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredSession?> read() async => value;

  @override
  Future<void> write(StoredSession session) async => value = session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AuthService enjekte edilen güvenli oturumu geri yükler ve temizler',
      () async {
    final storage = MemorySessionStorage()
      ..value = const StoredSession(
        token: 'secure-token',
        userId: 'u1',
        email: 'ada@example.com',
        displayName: 'Ada',
      );
    final auth = AuthService()..setSessionStorageForTesting(storage);

    expect(await auth.restoreSession(), isTrue);
    expect(auth.token, 'secure-token');
    expect(auth.currentUser?.displayName, 'Ada');

    await auth.logout();
    expect(storage.value, isNull);
    expect(auth.isLoggedIn, isFalse);
  });

  test('eksik oturum güvenli biçimde giriş yapılmamış sayılır', () async {
    final storage = MemorySessionStorage();
    final auth = AuthService()..setSessionStorageForTesting(storage);

    expect(await auth.restoreSession(), isFalse);
    expect(auth.isLoggedIn, isFalse);
  });

  test('geçici refresh ağ hatası yerel oturumu silmez', () async {
    final storage = MemorySessionStorage()
      ..value = const StoredSession(
        token: 'expired-access-token',
        refreshToken: 'refresh-token',
        userId: 'u-offline',
        email: 'offline@example.com',
        displayName: 'Offline',
      );
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        if (request.url.path == '/auth/me') {
          return http.Response('{"error":"expired"}', 401);
        }
        throw Exception('offline');
      }),
    );
    final auth = AuthService()
      ..setDependenciesForTesting(AuthDependencies.fromCore(
        sessionStorage: storage,
        apiClient: client,
        googleAuthProvider: GoogleSignInProvider(),
      ));

    expect(await auth.restoreSession(), isTrue);
    expect(await auth.verifySession(), isTrue);
    expect(auth.isLoggedIn, isTrue);
    expect(storage.value, isNotNull);
  });

  test('oturum notifier giriş ve çıkış değişikliklerini atomik yayınlar',
      () async {
    final storage = MemorySessionStorage()
      ..value = const StoredSession(
        token: 'reactive-token',
        userId: 'u-reactive',
        email: 'reactive@example.com',
        displayName: 'Reaktif',
      );
    final auth = AuthService()..setSessionStorageForTesting(storage);
    await auth.logout();
    storage.value = const StoredSession(
      token: 'reactive-token',
      userId: 'u-reactive',
      email: 'reactive@example.com',
      displayName: 'Reaktif',
    );

    final states = <AuthSessionState>[];
    void listener() => states.add(auth.sessionState.value);
    auth.sessionState.addListener(listener);
    addTearDown(() => auth.sessionState.removeListener(listener));

    expect(await auth.restoreSession(), isTrue);
    expect(states.last.isAuthenticated, isTrue);
    expect(states.last.user?.displayName, 'Reaktif');
    expect(states.last.token, 'reactive-token');

    await auth.logout();
    expect(states.last.isAuthenticated, isFalse);
    expect(states.last.user, isNull);
    expect(states.last.token, isNull);
  });
}
