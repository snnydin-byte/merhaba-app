import '../models/app_user.dart';

/// Uygulamanın tek ve atomik oturum görünümü.
///
/// Token ile kullanıcı ayrı ayrı yayınlanmadığı için dinleyiciler hiçbir
/// zaman "token var ama kullanıcı yok" gibi yarım bir ara durum görmez.
class AuthSessionState {
  final String? token;
  final AppUser? user;

  const AuthSessionState._({required this.token, required this.user});

  const AuthSessionState.signedOut() : this._(token: null, user: null);

  const AuthSessionState.authenticated({
    required String token,
    required AppUser user,
  }) : this._(token: token, user: user);

  bool get isAuthenticated => token != null && user != null;
}
