import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import 'auth_api_client.dart';
import 'auth_exception.dart';

/// Profil verisini ve profil medyalarını signaling API ile eşitler.
///
/// Bu sınıf oturum durumunu tutmaz; geçerli bearer token çağıran servis
/// tarafından verilir. Böylece ağ davranışı AuthService'ten bağımsız test
/// edilebilir ve profil ekranları büyüdükçe auth yaşam döngüsünü şişirmez.
class ProfileRepository {
  ProfileRepository({required AuthApiClient apiClient})
      : _apiClient = apiClient;

  final AuthApiClient _apiClient;

  Future<AppUser> updateProfile({
    required String token,
    required String fallbackDisplayName,
    String? displayName,
    String? bio,
    String? gender,
    List<String>? interests,
    String? country,
    String? language,
    bool? hideOnlineStatus,
    bool? hideLastSeen,
    bool? readReceiptsEnabled,
    String? birthDate,
    bool? discoverInvisible,
    List<String>? profileBadges,
    Map<String, int>? compatibilityAnswers,
    AvatarConfig? avatarConfig,
    bool clearAvatarConfig = false,
  }) async {
    final body = <String, dynamic>{
      'displayName': displayName ?? fallbackDisplayName,
    };
    if (bio != null) body['bio'] = bio;
    if (gender != null) body['gender'] = gender;
    if (interests != null) body['interests'] = interests;
    if (country != null) body['country'] = country;
    if (language != null) body['language'] = language;
    if (hideOnlineStatus != null) body['hideOnlineStatus'] = hideOnlineStatus;
    if (hideLastSeen != null) body['hideLastSeen'] = hideLastSeen;
    if (readReceiptsEnabled != null) {
      body['readReceiptsEnabled'] = readReceiptsEnabled;
    }
    if (birthDate != null) body['birthDate'] = birthDate;
    if (discoverInvisible != null) {
      body['discoverInvisible'] = discoverInvisible;
    }
    if (profileBadges != null) body['profileBadges'] = profileBadges;
    if (compatibilityAnswers != null) {
      body['compatibilityAnswers'] = compatibilityAnswers;
    }
    if (avatarConfig != null) {
      body['avatarConfig'] = avatarConfig.toJson();
    } else if (clearAvatarConfig) {
      body['avatarConfig'] = null;
    }

    final response = await _apiClient.put(
      '/profile',
      body: body,
      token: token,
    );
    return _userFromResponse(response);
  }

  Future<AppUser> uploadProfilePhoto({
    required String token,
    required File file,
  }) {
    return _upload(
      token: token,
      path: '/profile/photo',
      fieldName: 'photo',
      file: file,
      timeout: const Duration(seconds: 20),
      failureMessage: 'Fotoğraf yüklenemedi, tekrar dene.',
    );
  }

  Future<AppUser> removeProfilePhoto({required String token}) async {
    final response = await _apiClient.delete('/profile/photo', token: token);
    return _userFromResponse(response);
  }

  Future<AppUser> uploadIntroVideo({
    required String token,
    required File file,
  }) {
    return _upload(
      token: token,
      path: '/profile/intro-video',
      fieldName: 'video',
      file: file,
      timeout: const Duration(seconds: 40),
      failureMessage: 'Video yüklenemedi, tekrar dene.',
    );
  }

  Future<AppUser> removeIntroVideo({required String token}) async {
    final response = await _apiClient.delete(
      '/profile/intro-video',
      token: token,
    );
    return _userFromResponse(response);
  }

  Future<AppUser> uploadSelfieVerification({
    required String token,
    required File file,
  }) {
    return _upload(
      token: token,
      path: '/profile/selfie-verification',
      fieldName: 'photo',
      file: file,
      timeout: const Duration(seconds: 20),
      failureMessage: 'Fotoğraf yüklenemedi, tekrar dene.',
    );
  }

  Future<AppUser> _upload({
    required String token,
    required String path,
    required String fieldName,
    required File file,
    required Duration timeout,
    required String failureMessage,
  }) async {
    try {
      final response = await _apiClient.multipart(
        'POST',
        path,
        token: token,
        files: [
          await http.MultipartFile.fromPath(fieldName, file.path),
        ],
        timeout: timeout,
      );
      return _userFromResponse(response);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException(failureMessage);
    }
  }

  AppUser _userFromResponse(http.Response response) {
    final data = _apiClient.decodeOrThrow(response);
    final rawUser = data['user'];
    if (rawUser is! Map<String, dynamic>) {
      throw AuthException('Sunucudan geçersiz kullanıcı bilgisi geldi.');
    }
    return AppUser.fromJson(rawUser);
  }
}
