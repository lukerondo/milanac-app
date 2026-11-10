import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../errors.dart';
import 'providers.dart';

/// Come si entra nel club (migrazione 0037): con la password di iscrizione che il Direttivo
/// dà ai nuovi, oppure non si entra finché il Direttivo non la imposta.
enum SignupStatus {
  /// Nessun controllo, o password già data: si prosegue.
  open,

  /// Va scritta la password del club.
  password,

  /// Iscrizioni chiuse: il Direttivo non ha (ancora) impostato la password.
  closed,
}

/// Risposta di `signup_status` e `my_signup_gate`.
SignupStatus signupStatusOf(Object? value) => switch (value) {
  'password' => SignupStatus.password,
  'chiuse' => SignupStatus.closed,
  _ => SignupStatus.open,
};

/// Errore della password del club, con il testo già pronto da mostrare.
class SignupGateError extends AppError {
  const SignupGateError(super.message);
}

const wrongClubPasswordText =
    'Password del club non corretta: chiedila al Direttivo.';
const signupsClosedText =
    'Le iscrizioni sono chiuse: le riapre il Direttivo. '
    'Se hai già un account, accedi.';

abstract class SignupGateRepository {
  /// Prima di creare un account: serve la password, sono chiuse o si va avanti.
  Future<SignupStatus> status();

  /// In registrazione, per l'account collegato: [SignupStatus.open] se la password è
  /// già stata data (creando l'account) o non serve.
  Future<SignupStatus> myStatus();

  /// Chiede il via libera per creare l'account con [email]: vale 30 minuti.
  /// Lancia [SignupGateError] se la password è sbagliata o le iscrizioni sono chiuse.
  Future<void> requestSignup(String email, String clubPassword);

  /// Imposta o cambia la password di iscrizione (solo Direttivo). Vuota = iscrizioni chiuse.
  Future<void> setPassword(String next);
}

final signupGateRepositoryProvider = Provider<SignupGateRepository>((ref) {
  if (AppConfig.isDemo) return DemoSignupGateRepository();
  return _SupabaseSignupGateRepository(ref);
});

/// Stato delle iscrizioni per la schermata di accesso (si rilegge a ogni apertura).
final signupStatusProvider = FutureProvider.autoDispose<SignupStatus>(
  (ref) => ref.watch(signupGateRepositoryProvider).status(),
);

/// Se chi si sta registrando deve ancora scrivere la password del club.
final mySignupGateProvider = FutureProvider.autoDispose<SignupStatus>((ref) {
  // Cambio di account: si richiede da capo.
  ref.watch(currentUserIdProvider);
  return ref.watch(signupGateRepositoryProvider).myStatus();
});

class _SupabaseSignupGateRepository implements SignupGateRepository {
  _SupabaseSignupGateRepository(this._ref);
  final Ref _ref;

  /// Database non ancora aggiornato (manca la funzione): nessun controllo, come prima.
  Future<SignupStatus> _read(String function) async {
    try {
      return signupStatusOf(await _ref.read(supabaseProvider).rpc(function));
    } catch (e) {
      if (isMissingFunction(e)) return SignupStatus.open;
      rethrow;
    }
  }

  @override
  Future<SignupStatus> status() => _read('signup_status');

  @override
  Future<SignupStatus> myStatus() => _read('my_signup_gate');

  @override
  Future<void> requestSignup(String email, String clubPassword) async {
    final Object? result;
    try {
      result = await _ref
          .read(supabaseProvider)
          .rpc(
            'request_signup',
            params: {'p_email': email.trim(), 'p_club_password': clubPassword},
          );
    } catch (e) {
      if (isMissingFunction(e)) return;
      rethrow;
    }
    // La password sbagliata arriva come risposta (così il tentativo resta contato).
    if (result == 'password_errata') {
      throw const SignupGateError(wrongClubPasswordText);
    }
    if (result == 'chiuse') throw const SignupGateError(signupsClosedText);
  }

  @override
  Future<void> setPassword(String next) async {
    await _ref
        .read(supabaseProvider)
        .rpc('set_signup_password', params: {'p_new': next});
  }
}

/// In demo (e nei test) le iscrizioni sono aperte; [password] e [closed] si impostano
/// per provare le schermate.
class DemoSignupGateRepository implements SignupGateRepository {
  DemoSignupGateRepository({this.password, this.mine = SignupStatus.open});

  /// Password del club della sola demo (null = iscrizioni aperte, '' = chiuse).
  String? password;

  /// Risposta per chi si sta registrando.
  SignupStatus mine;

  /// Email che hanno avuto il via libera.
  final approved = <String>[];

  @override
  Future<SignupStatus> status() async => switch (password) {
    null => SignupStatus.open,
    '' => SignupStatus.closed,
    _ => SignupStatus.password,
  };

  @override
  Future<SignupStatus> myStatus() async => mine;

  @override
  Future<void> requestSignup(String email, String clubPassword) async {
    if (password == null) return;
    if (password!.isEmpty) throw const SignupGateError(signupsClosedText);
    if (clubPassword != password) {
      throw const SignupGateError(wrongClubPasswordText);
    }
    approved.add(email.trim());
  }

  @override
  Future<void> setPassword(String next) async => password = next;
}

/// Errore sulla password del club (sbagliata, troppi tentativi, iscrizioni chiuse): si
/// mostra sul campo.
bool isClubPasswordError(Object e) {
  if (e is SignupGateError) return true;
  final text = friendlyError(e).toLowerCase();
  return text.contains('password del club') ||
      text.contains('password di iscrizione');
}
