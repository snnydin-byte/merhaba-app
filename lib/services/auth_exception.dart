/// Sunucudan dönen kullanıcıya-gösterilebilir kimlik doğrulama hatası.
class AuthException implements Exception {
  AuthException(
    this.message, {
    this.code,
    this.statusCode,
  });

  final String message;
  final String? code;
  final int? statusCode;

  bool get requiresAgeVerification => code == 'AGE_VERIFICATION_REQUIRED';
  bool get isAgeRestricted => code == 'AGE_RESTRICTED';

  @override
  String toString() => message;
}
