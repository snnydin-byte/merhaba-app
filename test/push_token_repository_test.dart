import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merhaba_app/services/auth_exception.dart';
import 'package:merhaba_app/services/push_token_repository.dart';

const _authToken = 'header.payload.signature';
const _deviceToken = 'device-token-abcdefghijklmnopqrstuvwxyz-123456';

void main() {
  test('register bearer token, platform ve cihaz tokenını gönderir', () async {
    late http.Request captured;
    final repository = PushTokenRepository(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 201);
      }),
    );

    await repository.register(
      authToken: _authToken,
      deviceToken: _deviceToken,
      platform: 'android',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/push-token');
    expect(captured.headers['authorization'], 'Bearer $_authToken');
    expect(jsonDecode(captured.body), {
      'token': _deviceToken,
      'platform': 'android',
    });
  });

  test('unregister JSON gövdeli DELETE gönderir', () async {
    late http.Request captured;
    final repository = PushTokenRepository(
      baseUrl: 'https://api.example.com',
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 204);
      }),
    );

    await repository.unregister(
      authToken: _authToken,
      deviceToken: _deviceToken,
    );

    expect(captured.method, 'DELETE');
    expect(captured.headers['authorization'], 'Bearer $_authToken');
    expect(jsonDecode(captured.body), {'token': _deviceToken});
  });

  test('sunucu hata mesajını AuthException olarak döndürür', () async {
    final repository = PushTokenRepository(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async =>
          http.Response(jsonEncode({'error': 'Token reddedildi'}), 400)),
    );

    expect(
      () => repository.register(
        authToken: _authToken,
        deviceToken: _deviceToken,
        platform: 'ios',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'Token reddedildi',
        ),
      ),
    );
  });

  test('geçersiz platformu ağ çağrısı yapmadan reddeder', () async {
    var called = false;
    final repository = PushTokenRepository(
      baseUrl: 'https://api.example.com',
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    expect(
      () => repository.register(
        authToken: _authToken,
        deviceToken: _deviceToken,
        platform: 'web',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(called, isFalse);
  });
}
