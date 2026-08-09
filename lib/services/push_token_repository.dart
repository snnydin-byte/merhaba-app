import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_exception.dart';

/// Push cihaz tokenlarının signaling sunucusundaki kullanıcı hesabına
/// bağlanmasını ve hesaptan ayrılmasını yönetir.
///
/// Firebase/işletim sistemi bağımlılıklarını bilmez; böylece HTTP davranışı
/// sahte bir [http.Client] ile bağımsız olarak test edilebilir.
class PushTokenRepository {
  PushTokenRepository({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<void> register({
    required String authToken,
    required String deviceToken,
    required String platform,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _validate(authToken: authToken, deviceToken: deviceToken);
    if (platform != 'ios' && platform != 'android') {
      throw AuthException('Geçersiz bildirim platformu.');
    }

    final response = await _send(
      () => _client.post(
        Uri.parse('$baseUrl/push-token'),
        headers: _headers(authToken),
        body: jsonEncode({'token': deviceToken, 'platform': platform}),
      ),
      timeout,
    );
    _ensureSuccess(response);
  }

  Future<void> unregister({
    required String authToken,
    required String deviceToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _validate(authToken: authToken, deviceToken: deviceToken);

    // package:http Client.delete gövdeli DELETE'i bütün istemci
    // implementasyonlarında tutarlı biçimde desteklemediği için Request
    // kullanıyoruz. Backend tokenı JSON gövdesinden bekliyor.
    final request = http.Request(
      'DELETE',
      Uri.parse('$baseUrl/push-token'),
    )
      ..headers.addAll(_headers(authToken))
      ..body = jsonEncode({'token': deviceToken});

    final streamed = await _send(() => _client.send(request), timeout);
    final response = await http.Response.fromStream(streamed);
    _ensureSuccess(response);
  }

  Map<String, String> _headers(String authToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      };

  void _validate({required String authToken, required String deviceToken}) {
    if (authToken.trim().isEmpty) {
      throw AuthException('Bildirim tokenı için geçerli oturum gerekli.');
    }
    final normalized = deviceToken.trim();
    if (normalized.length < 20 || normalized.length > 4096) {
      throw AuthException('Geçersiz cihaz bildirim tokenı.');
    }
  }

  Future<T> _send<T>(Future<T> Function() operation, Duration timeout) async {
    try {
      return await operation().timeout(timeout);
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException('Bildirim sunucusuna ulaşılamıyor.');
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String? message;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message = decoded['error'] as String?;
      }
    } catch (_) {
      // JSON olmayan hata yanıtında genel mesaj kullanılır.
    }
    throw AuthException(message ?? 'Bildirim tokenı güncellenemedi.');
  }

  void close() => _client.close();
}
