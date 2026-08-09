import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merhaba_app/models/app_user.dart';
import 'package:merhaba_app/services/account_repository.dart';
import 'package:merhaba_app/services/auth_api_client.dart';
import 'package:merhaba_app/services/auth_exception.dart';
import 'package:merhaba_app/services/relationship_repository.dart';
import 'package:merhaba_app/services/utility_repository.dart';

void main() {
  test('hesap silme bearer token ile DELETE gönderir', () async {
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/profile');
        expect(request.headers['authorization'], 'Bearer secure-token');
        return http.Response('{"ok":true}', 200);
      }),
    );

    await AccountRepository(apiClient: client)
        .deleteAccount(token: 'secure-token');
  });

  test('yakın arkadaş cevabı liste değilse kontrollü hata verir', () async {
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient(
        (_) async => http.Response('{"closeFriendIds":null}', 200),
      ),
    );

    expect(
      () => RelationshipRepository(apiClient: client).toggleCloseFriend(
        token: 'secure-token',
        friendId: 'friend/with slash',
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test('arkadaş raporu hedef kimliğini URL için encode eder', () async {
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/friends/friend%2Fid/report');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reason'], 'spam');
        return http.Response('{"ok":true}', 200);
      }),
    );

    await RelationshipRepository(apiClient: client).reportFriend(
      token: 'secure-token',
      friendId: 'friend/id',
      reason: 'spam',
    );
  });

  test('güvenilir kişi güncellemesi kullanıcı modelini döndürür', () async {
    final client = AuthApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect((body['contacts'] as List).length, 1);
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'u1',
              'email': 'ada@example.com',
              'displayName': 'Ada',
            },
          }),
          200,
        );
      }),
    );

    final user =
        await UtilityRepository(apiClient: client).updateTrustedContacts(
      token: 'secure-token',
      contacts: const [TrustedContact(name: 'Ali', phone: '+905551112233')],
    );
    expect(user.id, 'u1');
  });
}
