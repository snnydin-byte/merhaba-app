import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merhaba_app/services/auth_api_client.dart';
import 'package:merhaba_app/services/auth_exception.dart';

void main() {
  test('JSON object response is decoded', () async {
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/auth/login');
        expect(request.headers['content-type'], 'application/json');
        return http.Response('{"token":"abc"}', 200);
      }),
    );

    final response = await client.post(
      '/auth/login',
      body: {'email': 'test@example.com'},
    );

    expect(client.decodeOrThrow(response)['token'], 'abc');
  });

  test('server error becomes AuthException', () {
    final client = AuthApiClient(baseUrl: 'https://example.test');
    expect(
      () => client.decodeOrThrow(http.Response(
        '{"error":"Reddedildi","code":"AGE_RESTRICTED"}',
        403,
      )),
      throwsA(
        isA<AuthException>()
            .having((error) => error.message, 'message', 'Reddedildi')
            .having((error) => error.code, 'code', 'AGE_RESTRICTED')
            .having((error) => error.statusCode, 'statusCode', 403),
      ),
    );
  });

  test('non-object JSON is rejected', () {
    final client = AuthApiClient(baseUrl: 'https://example.test');
    expect(
      () => client.decodeOrThrow(http.Response('[]', 200)),
      throwsA(isA<AuthException>()),
    );
  });

  test('PUT and DELETE include bearer token', () async {
    final methods = <String>[];
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        methods.add(request.method);
        expect(request.headers['authorization'], 'Bearer secure-token');
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.put(
      '/profile',
      body: {'displayName': 'Ada'},
      token: 'secure-token',
    );
    await client.delete('/profile/photo', token: 'secure-token');

    expect(methods, ['PUT', 'DELETE']);
  });
}
