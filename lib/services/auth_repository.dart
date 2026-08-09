import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import 'auth_api_client.dart';
import 'auth_exception.dart';
import 'google_auth_provider.dart';

class AuthSession {
  const AuthSession(
      {required this.token, this.refreshToken, required this.user});

  final String token;
  final String? refreshToken;
  final AppUser user;
}

class SessionVerification {
  const SessionVerification._({this.user, required this.isUnauthorized});

  const SessionVerification.valid(AppUser user)
      : this._(user: user, isUnauthorized: false);

  const SessionVerification.keepLocalSession() : this._(isUnauthorized: false);

  const SessionVerification.unauthorized() : this._(isUnauthorized: true);

  final AppUser? user;
  final bool isUnauthorized;
}

class AuthRepository {
  AuthRepository({
    required AuthApiClient apiClient,
    GoogleAuthProvider? googleAuthProvider,
  })  : _apiClient = apiClient,
        _googleAuthProvider = googleAuthProvider ?? GoogleSignInProvider();

  final AuthApiClient _apiClient;
  GoogleAuthProvider _googleAuthProvider;

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required String birthDate,
    required bool adultConfirmed,
  }) async {
    final response = await _apiClient.post(
      '/auth/register',
      body: {
        'email': email,
        'password': password,
        'displayName': displayName,
        'birthDate': birthDate,
        'adultConfirmed': adultConfirmed,
      },
    );
    return _decodeSession(response);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    String? birthDate,
    bool adultConfirmed = false,
  }) async {
    final response = await _apiClient.post(
      '/auth/login',
      body: {
        'email': email,
        'password': password,
        if (birthDate != null) 'birthDate': birthDate,
        if (birthDate != null) 'adultConfirmed': adultConfirmed,
      },
    );
    return _decodeSession(response);
  }

  Future<AuthSession?> signInWithGoogle({
    String? birthDate,
    bool adultConfirmed = false,
  }) async {
    if (!isGoogleSignInConfigured) {
      throw AuthException('Google ile giriş şu an yapılandırılmamış.');
    }

    final idToken = await _googleAuthProvider.requestIdToken();
    if (idToken == null) return null;

    final response = await _apiClient.post(
      '/auth/google',
      body: {
        'idToken': idToken,
        if (birthDate != null) 'birthDate': birthDate,
        if (birthDate != null) 'adultConfirmed': adultConfirmed,
      },
    );
    return _decodeSession(response);
  }

  Future<AuthSession> refreshSession(String refreshToken) async {
    final response = await _apiClient.post(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
      timeout: const Duration(seconds: 8),
    );
    return _decodeSession(response);
  }

  Future<void> revokeRefreshToken(String refreshToken) async {
    try {
      await _apiClient.post(
        '/auth/logout',
        body: {'refreshToken': refreshToken},
        timeout: const Duration(seconds: 4),
      );
    } catch (_) {
      // Yerel logout sunucu erişilemiyor diye kilitlenmemeli. Refresh token
      // cihazdan yine silinir; sunucudaki kayıt TTL sonunda sona erer.
    }
  }

  Future<SessionVerification> verifySession(String token) async {
    try {
      final response = await _apiClient.get(
        '/auth/me',
        token: token,
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 428) {
        return const SessionVerification.unauthorized();
      }
      if (response.statusCode != 200) {
        return const SessionVerification.keepLocalSession();
      }

      final data = _apiClient.decodeOrThrow(response);
      final rawUser = data['user'];
      if (rawUser is! Map<String, dynamic>) {
        throw AuthException('Sunucudan geçersiz kullanıcı bilgisi geldi.');
      }
      return SessionVerification.valid(AppUser.fromJson(rawUser));
    } on AuthException {
      // Ağ, timeout veya beklenmeyen geçici sunucu yanıtında cihazdaki
      // oturumu koru. Sunucunun açıkça 401 döndürmesi yukarıda ayrıştırılır.
      return const SessionVerification.keepLocalSession();
    }
  }

  void setGoogleAuthProviderForTesting(GoogleAuthProvider provider) {
    _googleAuthProvider = provider;
  }

  AuthSession _decodeSession(http.Response response) {
    final data = _apiClient.decodeOrThrow(response);
    final token = data['token'];
    final refreshToken = data['refreshToken'];
    final rawUser = data['user'];
    if (token is! String || token.isEmpty || rawUser is! Map<String, dynamic>) {
      throw AuthException('Sunucudan geçersiz oturum bilgisi geldi.');
    }
    return AuthSession(
      token: token,
      refreshToken: refreshToken is String && refreshToken.isNotEmpty
          ? refreshToken
          : null,
      user: AppUser.fromJson(rawUser),
    );
  }
}
