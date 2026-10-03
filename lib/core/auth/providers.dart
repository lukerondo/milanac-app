import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'auth_repository.dart';
import 'profile.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

/// Sessione corrente (null = non autenticato). In demo è sempre "autenticato".
final sessionProvider = StreamProvider<Session?>((ref) {
  if (AppConfig.isDemo) return Stream.value(null);
  final auth = ref.watch(supabaseProvider).auth;
  return auth.onAuthStateChange
      .map((e) => e.session)
      .startWith(auth.currentSession);
});

/// Profilo del club dell'utente loggato, aggiornato in tempo reale
/// (così quando il Direttivo approva l'utente, l'app si sblocca da sola).
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
