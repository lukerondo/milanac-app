import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Metodi di accesso social offerti nella schermata di login.
enum LoginMethod { google, microsoft, yahoo, apple }

/// Esito della registrazione con email: con la conferma dell'email attiva,
/// la sessione parte solo dopo aver aperto il link ricevuto.
enum EmailSignUpResult { needsConfirmation, signedIn }

abstract class AuthRepository {
  Future<void> signIn(LoginMethod method);
  Future<void> signInWithEmail(String email, String password);
  Future<EmailSignUpResult> signUpWithEmail(String email, String password);
  Future<void> resendConfirmation(String email);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();

  /// Elimina definitivamente l'account (funzione `delete_my_account` nel database).
  Future<void> deleteAccount();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  String? get _redirect => kIsWeb ? null : AppConfig.authRedirect;

  @override
  Future<void> signIn(LoginMethod method) async {
    switch (method) {
      case LoginMethod.google:
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: _redirect,
        );
      case LoginMethod.microsoft:
        // Account personali Microsoft (Hotmail/Outlook/Live) tramite provider Azure, tenant "common".
        await _client.auth.signInWithOAuth(
          OAuthProvider.azure,
          redirectTo: _redirect,
          scopes: 'email openid profile',
        );
      case LoginMethod.apple:
        await _client.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: _redirect,
        );
      case LoginMethod.yahoo:
        // Provider OIDC personalizzato configurato in Supabase con identificativo "custom:yahoo".
        await _client.auth.signInWithOAuth(
          const OAuthProvider('custom:yahoo'),
          redirectTo: _redirect,
          scopes: 'openid email profile',
        );
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  @override
  Future<EmailSignUpResult> signUpWithEmail(
    String email,
    String password,
  ) async {
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _redirect,
    );
    return res.session == null
        ? EmailSignUpResult.needsConfirmation
        : EmailSignUpResult.signedIn;
  }

  @override
  Future<void> resendConfirmation(String email) => _client.auth.resend(
    type: OtpType.signup,
    email: email.trim(),
    emailRedirectTo: _redirect,
  );

  @override
  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email.trim(), redirectTo: _redirect);

  @override
  Future<void> updatePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    await _client.rpc('delete_my_account');
    await _client.auth.signOut();
  }
}

/// In demo (e nei test) non c'è nessun server: ogni azione è un finto successo.
class DemoAuthRepository implements AuthRepository {
  @override
  Future<void> signIn(LoginMethod method) async {}
  @override
  Future<void> signInWithEmail(String email, String password) async {}
  @override
  Future<EmailSignUpResult> signUpWithEmail(
    String email,
    String password,
  ) async => EmailSignUpResult.needsConfirmation;
  @override
  Future<void> resendConfirmation(String email) async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> updatePassword(String newPassword) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

/// Messaggio comprensibile per gli errori di accesso più comuni.
String friendlyAuthError(Object e) {
  final msg = e is AuthException ? e.message : e.toString();
  final m = msg.toLowerCase();
  if (m.contains('invalid login credentials')) {
    return 'Email o password non corretti.';
  }
  if (m.contains('email not confirmed')) {
    return 'Conferma prima la tua email: apri il link che ti abbiamo inviato.';
  }
  if (m.contains('already registered') ||
      m.contains('already been registered')) {
    return 'Esiste già un account con questa email: prova ad accedere.';
  }
  if (m.contains('password should be')) {
    return 'La password è troppo corta.';
  }
  if (m.contains('rate limit') || m.contains('too many')) {
    return 'Troppi tentativi: riprova tra qualche minuto.';
  }
  if (m.contains('invalid email') || m.contains('unable to validate email')) {
    return 'Indirizzo email non valido.';
  }
  if (m.contains('socket') ||
      m.contains('network') ||
      m.contains('failed host')) {
    return 'Nessuna connessione: controlla la rete e riprova.';
  }
  return 'Operazione non riuscita: $msg';
}
