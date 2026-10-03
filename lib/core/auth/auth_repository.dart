import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Metodi di accesso offerti nella schermata di login.
enum LoginMethod { google, microsoft, yahoo, apple }

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<void> signIn(LoginMethod method) async {
    final redirect = kIsWeb ? null : AppConfig.authRedirect;
    switch (method) {
      case LoginMethod.google:
        await _client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirect);
      case LoginMethod.microsoft:
        // Account personali Microsoft (Hotmail/Outlook/Live) tramite provider Azure, tenant "common".
        await _client.auth.signInWithOAuth(
          OAuthProvider.azure,
          redirectTo: redirect,
          scopes: 'email openid profile',
        );
      case LoginMethod.apple:
        await _client.auth.signInWithOAuth(OAuthProvider.apple, redirectTo: redirect);
      case LoginMethod.yahoo:
        // Provider OIDC personalizzato configurato in Supabase con identificativo "custom:yahoo".
        await _client.auth.signInWithOAuth(
          const OAuthProvider('custom:yahoo'),
          redirectTo: redirect,
          scopes: 'openid email profile',
        );
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
