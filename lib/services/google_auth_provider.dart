import 'package:google_sign_in/google_sign_in.dart';

import 'auth_exception.dart';

const String googleWebClientId =
    '237640279761-pov3sop9c2fjmfc2ooe75lsnpti7e1ra.apps.googleusercontent.com';

bool get isGoogleSignInConfigured =>
    !googleWebClientId.startsWith('REPLACE_WITH_');

abstract class GoogleAuthProvider {
  Future<String?> requestIdToken();
}

class GoogleSignInProvider implements GoogleAuthProvider {
  GoogleSignInProvider({GoogleSignIn? googleSignIn})
      : _googleSignIn =
            googleSignIn ?? GoogleSignIn(serverClientId: googleWebClientId);

  final GoogleSignIn _googleSignIn;

  @override
  Future<String?> requestIdToken() async {
    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signIn();
    } catch (_) {
      throw AuthException('Google ile giriş başlatılamadı, tekrar dene.');
    }
    if (account == null) return null;

    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthException(
        'Google kimlik doğrulaması eksik döndü, tekrar dene.',
      );
    }
    return idToken;
  }
}
