import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'auth_repository.dart';
import 'profile.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.isDemo) return DemoAuthRepository();
  return SupabaseAuthRepository(ref.watch(supabaseProvider));
});

/// Sessione corrente (null = non autenticato). In demo è sempre "autenticato".
final sessionProvider = StreamProvider<Session?>((ref) {
  if (AppConfig.isDemo) return Stream.value(null);
  final auth = ref.watch(supabaseProvider).auth;
  return auth.onAuthStateChange
      .map((e) => e.session)
      .startWith(auth.currentSession);
});

/// true dopo aver aperto il link "password dimenticata": l'app chiede la nuova password.
final passwordRecoveryProvider = NotifierProvider<PasswordRecovery, bool>(
  PasswordRecovery.new,
);

class PasswordRecovery extends Notifier<bool> {
  @override
  bool build() {
    if (!AppConfig.isDemo) {
      final sub = ref.watch(supabaseProvider).auth.onAuthStateChange.listen((
        e,
      ) {
        if (e.event == AuthChangeEvent.passwordRecovery) state = true;
      });
      ref.onDispose(sub.cancel);
    }
    return false;
  }

  void start() => state = true;
  void done() => state = false;
}

/// Profilo del club dell'utente loggato, aggiornato in tempo reale
/// (registrazione completata, regolamento accettato, ruolo assegnato).
final profileProvider = StreamProvider<Profile?>((ref) {
  if (AppConfig.isDemo) return Stream.value(Profile.demo);
  final session = ref.watch(sessionProvider).value;
  if (session == null) return Stream.value(null);
  return ref
      .watch(supabaseProvider)
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', session.user.id)
      .map((rows) => rows.isEmpty ? null : Profile.fromMap(rows.first));
});

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
