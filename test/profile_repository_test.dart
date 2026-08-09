import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merhaba_app/services/auth_api_client.dart';
import 'package:merhaba_app/services/auth_exception.dart';
import 'package:merhaba_app/services/profile_repository.dart';

const _userJson = {
  'id': 'u1',
  'email': 'ada@example.com',
  'displayName': 'Ada',
};

void main() {
  test('profil güncellemesi bearer token ve yalnızca verilen alanları yollar',
      () async {
    final apiClient = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/profile');
        expect(request.headers['authorization'], 'Bearer secure-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['displayName'], 'Ada');
        expect(body['bio'], 'Merhaba');
        expect(body.containsKey('country'), isFalse);
        return http.Response(jsonEncode({'user': _userJson}), 200);
      }),
    );
    final repository = ProfileRepository(apiClient: apiClient);

    final user = await repository.updateProfile(
      token: 'secure-token',
      fallbackDisplayName: 'Ada',
      bio: 'Merhaba',
    );

    expect(user.id, 'u1');
    expect(user.displayName, 'Ada');
  });

  test('profil silme cevabındaki geçersiz user alanı reddedilir', () async {
    final apiClient = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient(
        (_) async => http.Response('{"user":null}', 200),
      ),
    );
    final repository = ProfileRepository(apiClient: apiClient);

    expect(
      () => repository.removeProfilePhoto(token: 'secure-token'),
      throwsA(isA<AuthException>()),
    );
  });
}
