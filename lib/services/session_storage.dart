import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oturum bilgilerinin cihazda saklanmasını tek yerde toplar.
///
/// Erişim tokenı yalnızca platformun güvenli kasasında tutulur. Kullanıcı
/// kimliği ve ekranda hızlı başlangıç için gereken hassas olmayan özet alanlar
/// SharedPreferences içinde kalır.
abstract interface class SessionStorage {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

class StoredSession {
  const StoredSession({
    required this.token,
    this.refreshToken,
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final String token;
  final String? refreshToken;
  final String userId;
  final String email;
  final String displayName;
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _userIdKey = 'auth_user_id';
  static const _userEmailKey = 'auth_user_email';
  static const _userNameKey = 'auth_user_name';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<StoredSession?> read() async {
    final prefs = await SharedPreferences.getInstance();
    var token = await _secureStorage.read(key: _tokenKey);
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);

    // V1 öncesindeki düz metin tokenı bir defaya mahsus güvenli kasaya taşı.
    final legacyToken = prefs.getString(_tokenKey);
    if (token == null && legacyToken != null && legacyToken.isNotEmpty) {
      await _secureStorage.write(key: _tokenKey, value: legacyToken);
      await prefs.remove(_tokenKey);
      token = legacyToken;
    } else if (legacyToken != null) {
      // Güvenli kopya zaten varsa eski düz metin kalıntısını temizle.
      await prefs.remove(_tokenKey);
    }

    final userId = prefs.getString(_userIdKey);
    final email = prefs.getString(_userEmailKey);
    final displayName = prefs.getString(_userNameKey);
    if (token == null ||
        token.isEmpty ||
        userId == null ||
        email == null ||
        displayName == null) {
      return null;
    }

    return StoredSession(
      token: token,
      refreshToken: refreshToken,
      userId: userId,
      email: email,
      displayName: displayName,
    );
  }

  @override
  Future<void> write(StoredSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: _tokenKey, value: session.token);
    if (session.refreshToken != null && session.refreshToken!.isNotEmpty) {
      await _secureStorage.write(
          key: _refreshTokenKey, value: session.refreshToken);
    } else {
      await _secureStorage.delete(key: _refreshTokenKey);
    }
    await prefs.remove(_tokenKey);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_userEmailKey, session.email);
    await prefs.setString(_userNameKey, session.displayName);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userNameKey);
  }
}
