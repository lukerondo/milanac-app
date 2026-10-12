import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dati anagrafici: nome, cognome, anno e data di nascita. Dalla migrazione 0025 stanno
/// nella tabella `profile_private`, che leggono e scrivono solo l'interessato e il
/// Direttivo; prima erano colonne di `profiles`, leggibili da tutti i membri.
const privateFields = ['first_name', 'last_name', 'birth_year', 'birth_date'];

/// La tabella non c'è ancora (database prima della 0025): PostgREST risponde PGRST205,
/// le versioni meno recenti 42P01.
bool isMissingTable(Object e) =>
    e is PostgrestException && (e.code == 'PGRST205' || e.code == '42P01');

/// La riga di `profiles` con i dati anagrafici della sua riga di `profile_private`, se
/// c'è; senza restano quelli della riga (le colonne di prima della 0025, o nessuno).
Map<String, dynamic> withPrivateRow(
  Map<String, dynamic> profile,
  Map<String, dynamic>? private,
) => private == null
    ? profile
    : {...profile, for (final k in privateFields) k: private[k]};

/// Le righe di `profile_private` che l'utente può leggere (la propria; tutte per il
/// Direttivo), per id e in tempo reale. [id] limita alla riga di un solo membro.
Stream<Map<String, Map<String, dynamic>>> watchPrivateRows(
  SupabaseClient client, {
  String? id,
}) {
  final rows = client.from('profile_private').stream(primaryKey: ['id']);
  return privateRowsById(id == null ? rows : rows.eq('id', id));
}

/// [rows] per id, senza gli errori che non devono fermare la rosa o il profilo:
/// - tempo reale non attivo sulla tabella: restano i dati letti all'apertura;
/// - tabella che non c'è ancora (prima della 0025): nessuna riga, i dati anagrafici
///   arrivano con le colonne di `profiles` come prima;
/// - un altro rifiuto del database: niente dati anagrafici, ma la rosa resta.
///
/// Gli errori di rete passano: chi ascolta riprova da solo.
@visibleForTesting
Stream<Map<String, Map<String, dynamic>>> privateRowsById(
  Stream<List<Map<String, dynamic>>> rows,
) => rows
    .map((list) => {for (final r in list) r['id'] as String: r})
    .transform(
      StreamTransformer.fromHandlers(
        handleError: (error, stack, sink) {
          if (error is RealtimeSubscribeException) return;
          if (error is PostgrestException) {
            if (!isMissingTable(error)) {
              debugPrint('Dati anagrafici non disponibili: ${error.message}');
            }
            sink.add(const {});
            return;
          }
          sink.addError(error, stack);
        },
      ),
    );

/// Salva i dati anagrafici di [id] in `profile_private` (solo i campi in [data]: quelli
/// che mancano restano come sono). Prima della 0025 la tabella non c'è e l'errore
/// passa a chi chiama ([isMissingTable]), che li scrive in `profiles` come prima.
Future<void> savePrivateRow(
  SupabaseClient client,
  String id,
  Map<String, dynamic> data,
) async {
  if (data.isEmpty) return;
  await client.from('profile_private').upsert({'id': id, ...data});
}

/// L'ultimo valore di [a] e di [b] insieme, a ogni novità dell'uno o dell'altro (dal
/// primo momento in cui ci sono tutti e due). Gli errori passano; finisce quando sono
/// finiti tutti e due, o uno dei due senza aver mai dato un valore.
Stream<R> combineLatest<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> out;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false, hasB = false, doneA = false, doneB = false;

  void emit() {
    if (!hasA || !hasB) return;
    final R value;
    try {
      value = combine(lastA as A, lastB as B);
    } catch (e, s) {
      out.addError(e, s);
      return;
    }
    out.add(value);
  }

  void done() {
    if ((doneA && doneB) || (doneA && !hasA) || (doneB && !hasB)) {
      unawaited(out.close());
    }
  }

  out = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (v) {
          lastA = v;
          hasA = true;
          emit();
        },
        onError: out.addError,
        onDone: () {
          doneA = true;
          done();
        },
      );
      subB = b.listen(
        (v) {
          lastB = v;
          hasB = true;
          emit();
        },
        onError: out.addError,
        onDone: () {
          doneB = true;
          done();
        },
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return out.stream;
}
