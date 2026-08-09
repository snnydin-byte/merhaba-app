import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Oturum değişikliklerini yalnızca ihtiyaç duyan widget alt ağacında dinler.
/// Böylece profil fotoğrafı veya kullanıcı alanı güncellendiğinde bütün
/// MaterialApp/Navigator ağacı yeniden kurulmaz.
class AuthSessionBuilder extends StatelessWidget {
  const AuthSessionBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(
    BuildContext context,
    AuthSessionState session,
    AppUser? user,
  ) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthSessionState>(
      valueListenable: AuthService().sessionState,
      builder: (context, session, _) => builder(context, session, session.user),
    );
  }
}
