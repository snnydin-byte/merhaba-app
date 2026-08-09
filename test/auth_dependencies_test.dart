import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/auth_api_client.dart';
import 'package:merhaba_app/services/auth_dependencies.dart';
import 'package:merhaba_app/services/google_auth_provider.dart';
import 'package:merhaba_app/services/session_storage.dart';

class _MemorySessionStorage implements SessionStorage {
  StoredSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredSession?> read() async => value;

  @override
  Future<void> write(StoredSession session) async => value = session;
}

class _FakeGoogleProvider implements GoogleAuthProvider {
  @override
  Future<String?> requestIdToken() async => 'fake-token';
}

void main() {
  test('withApiClient bütün repository graphını yeni istemciyle kurar', () {
    final firstClient = AuthApiClient(baseUrl: 'https://first.example');
    final secondClient = AuthApiClient(baseUrl: 'https://second.example');
    final dependencies = AuthDependencies.fromCore(
      sessionStorage: _MemorySessionStorage(),
      apiClient: firstClient,
      googleAuthProvider: _FakeGoogleProvider(),
    );

    final updated = dependencies.withApiClient(secondClient);

    expect(updated.apiClient, same(secondClient));
    expect(updated.sessionStorage, same(dependencies.sessionStorage));
    expect(updated.googleAuthProvider, same(dependencies.googleAuthProvider));
    expect(updated.authRepository, isNot(same(dependencies.authRepository)));
    expect(
        updated.profileRepository, isNot(same(dependencies.profileRepository)));
    expect(
        updated.accountRepository, isNot(same(dependencies.accountRepository)));
  });

  test('withGoogleAuthProvider yalnızca auth graphını yeniler', () {
    final dependencies = AuthDependencies.fromCore(
      sessionStorage: _MemorySessionStorage(),
      apiClient: AuthApiClient(baseUrl: 'https://example.test'),
      googleAuthProvider: _FakeGoogleProvider(),
    );
    final newProvider = _FakeGoogleProvider();

    final updated = dependencies.withGoogleAuthProvider(newProvider);

    expect(updated.googleAuthProvider, same(newProvider));
    expect(updated.authRepository, isNot(same(dependencies.authRepository)));
    expect(updated.profileRepository, same(dependencies.profileRepository));
    expect(updated.utilityRepository, same(dependencies.utilityRepository));
  });
}
