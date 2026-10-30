import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/intro/intro_state.dart';
import '../config.dart';
import '../push/push_service.dart';
import 'auth_repository.dart';
import 'private_data.dart';
import 'profile.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.isDemo) return DemoAuthRepository();
  return SupabaseAuthRepository(ref.watch(supabaseProvider));
});

/// Sessione corrente (null = non autenticato). In demo è sempre "autenticato".
///
/// `onAuthStateChange` ripete a ogni nuovo ascolto tutta la storia, errori compresi (un
/// rinnovo del token fallito offline, un link scaduto): qui gli errori si scartano, se no
/// a ogni nuovo tentativo automatico il provider ripartirebbe e rileggerebbe lo stesso
/// errore. I link non validi li segnala [PasswordRecovery].
final sessionProvider = StreamProvider<Session?>((ref) {
  if (AppConfig.isDemo) return Stream.value(null);
  final auth = ref.watch(supabaseProvider).auth;
  return auth.onAuthStateChange
      .map((e) => e.session)
      .handleError((Object _) {})
      .startWith(auth.currentSession);
}, retry: (_, _) => null);

/// Id dell'utente loggato (null = nessuno). Cambia solo al cambio di account, non a ogni
/// rinnovo del token: i dati dell'utente (chat, proposte, ...) lo guardano così si
/// ricaricano da zero quando entra un altro account sullo stesso telefono.
final currentUserIdProvider = Provider<String?>((ref) {
  if (AppConfig.isDemo) return 'demo';
  return ref.watch(sessionProvider.select((s) => s.value?.user.id));
});

/// true dopo aver aperto il link "password dimenticata": l'app chiede la nuova password.
final passwordRecoveryProvider = NotifierProvider<PasswordRecovery, bool>(
  PasswordRecovery.new,
);

class PasswordRecovery extends Notifier<bool> {
  @override
  bool build() {
    if (!AppConfig.isDemo) {
      final sub = ref
          .watch(supabaseProvider)
          .auth
          .onAuthStateChange
          .listen(
            (e) {
              if (e.event == AuthChangeEvent.passwordRecovery) state = true;
              // Uscita (o sessione scaduta): il recupero è finito, al prossimo accesso
              // non si chiede di nuovo la nuova password.
              if (e.event == AuthChangeEvent.signedOut) state = false;
            },
            // Link dell'email scaduto o già usato: lo si dice invece di ignorarlo.
            onError: (Object e) {
              final text = authLinkErrorText(e);
              if (text != null) _notice(text);
            },
          );
      ref.onDispose(sub.cancel);
    }
    return false;
  }

  /// Un link aperto ad app chiusa dà errore durante l'intro: l'avviso aspetta che finisca.
  void _notice(String text) {
    void show() => showAppMessage(text, duration: const Duration(seconds: 8));
    if (ref.read(introDoneProvider)) {
      show();
    } else {
      ref.listen(introDoneProvider, (_, done) {
        if (done) show();
      });
    }
  }

  void start() => state = true;
  void done() => state = false;
}

/// In demo il profilo vive in memoria: quello che si cambia (es. le notifiche) resta,
/// come farebbe il tempo reale con il profilo vero.
final demoProfileProvider = NotifierProvider<DemoProfile, Profile>(
  DemoProfile.new,
);

class DemoProfile extends Notifier<Profile> {
  @override
  Profile build() => Profile.demo;

  void update(Profile Function(Profile current) change) =>
      state = change(state);
}

/// Profilo del club dell'utente loggato, aggiornato in tempo reale
/// (registrazione completata, regolamento accettato, ruolo assegnato), con i propri
/// dati anagrafici (`profile_private`).
final profileProvider = StreamProvider<Profile?>((ref) {
  if (AppConfig.isDemo) return Stream.value(ref.watch(demoProfileProvider));
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  final client = ref.watch(supabaseProvider);
  final profile = client
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', userId);
  return combineLatest(
    profile,
    watchPrivateRows(client, id: userId),
    (rows, private) => rows.isEmpty
        ? null
        : Profile.fromMap(withPrivateRow(rows.first, private[userId])),
  );
});

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
