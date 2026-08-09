import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_exception.dart';

class AuthApiClient {
  AuthApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<http.Response> get(
    String path, {
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await _client
          .get(Uri.parse('$baseUrl$path'), headers: _headers(token: token))
          .timeout(timeout);
    } catch (_) {
      throw _connectionException();
    }
  }

  Future<http.Response> post(
    String path, {
    required Map<String, dynamic> body,
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers(token: token, json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw _connectionException();
    }
  }

  Future<http.Response> put(
    String path, {
    required Map<String, dynamic> body,
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await _client
          .put(
            Uri.parse('$baseUrl$path'),
            headers: _headers(token: token, json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw _connectionException();
    }
  }

  Future<http.Response> delete(
    String path, {
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await _client
          .delete(Uri.parse('$baseUrl$path'), headers: _headers(token: token))
          .timeout(timeout);
    } catch (_) {
      throw _connectionException();
    }
  }

  Future<http.Response> multipart(
    String method,
    String path, {
    String? token,
    required List<http.MultipartFile> files,
    Map<String, String> fields = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final request = http.MultipartRequest(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll(_headers(token: token))
        ..fields.addAll(fields)
        ..files.addAll(files);
      final streamed = await _client.send(request).timeout(timeout);
      return http.Response.fromStream(streamed);
    } catch (_) {
      throw _connectionException();
    }
  }

  Map<String, dynamic> decodeOrThrow(http.Response response) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON object expected');
      }
      data = decoded;
    } catch (_) {
      throw AuthException('Sunucudan beklenmeyen bir yanıt geldi.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        data['error'] as String? ?? 'Bir şeyler ters gitti.',
        code: data['code'] as String?,
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Map<String, String> _headers({String? token, bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  AuthException _connectionException() => AuthException(
        'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun çalıştığından '
        've doğru adrese ayarlandığından emin ol.',
      );

  void close() => _client.close();
}
