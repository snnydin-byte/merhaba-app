import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merhaba_app/services/auth_api_client.dart';
import 'package:merhaba_app/services/auth_exception.dart';
import 'package:merhaba_app/services/auth_repository.dart';
import 'package:merhaba_app/services/google_auth_provider.dart';

class _FakeGoogleProvider implements GoogleAuthProvider {
  _FakeGoogleProvider(this.token);
  final String? token;

  @override
  Future<String?> requestIdToken() async => token;
}

Map<String, dynamic> _userJson({String name = 'Ada'}) => {
      'id': 'u1',
      'email': 'ada@example.com',
      'displayName': name,
    };

void main() {
  test('register oturum tokenı ve kullanıcıyı ayrıştırır', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/register');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['birthDate'], '1990-01-01');
      expect(body['adultConfirmed'], isTrue);
      return http.Response(
        jsonEncode({'token': 'jwt', 'user': _userJson()}),
        200,
      );
    });
    final repository = AuthRepository(
      apiClient: AuthApiClient(baseUrl: 'https://example.test', client: client),
    );

    final session = await repository.register(
      email: 'ada@example.com',
      password: '12345678',
      displayName: 'Ada',
      birthDate: '1990-01-01',
      adultConfirmed: true,
    );

    expect(session.token, 'jwt');
    expect(session.user.displayName, 'Ada');
  });

  test('geçersiz auth cevabı kontrollü hata üretir', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    final repository = AuthRepository(
      apiClient: AuthApiClient(baseUrl: 'https://example.test', client: client),
    );

    await expectLater(
      repository.login(email: 'a@b.com', password: '12345678'),
      throwsA(isA<AuthException>()),
    );
  });

  test('verifySession 401 için unauthorized döner', () async {
    final client = MockClient((_) async => http.Response('{"error":"x"}', 401));
    final repository = AuthRepository(
      apiClient: AuthApiClient(baseUrl: 'https://example.test', client: client),
    );

    final result = await repository.verifySession('bad-token');
    expect(result.isUnauthorized, isTrue);
  });

  test('verifySession bağlantı hatasında yerel oturumu korur', () async {
    final client = MockClient((_) async => throw Exception('offline'));
    final repository = AuthRepository(
      apiClient: AuthApiClient(baseUrl: 'https://example.test', client: client),
    );

    final result = await repository.verifySession('token');
    expect(result.isUnauthorized, isFalse);
    expect(result.user, isNull);
  });

  test('Google seçim iptalinde null döner ve backend çağrılmaz', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 500);
    });
    final repository = AuthRepository(
      apiClient: AuthApiClient(baseUrl: 'https://example.test', client: client),
      googleAuthProvider: _FakeGoogleProvider(null),
    );

    expect(await repository.signInWithGoogle(), isNull);
    expect(called, isFalse);
  });
}
