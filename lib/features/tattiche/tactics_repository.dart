import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../lavagna/board_model.dart';

const tacticsBucket = 'tactics';

/// Uno schema o una tattica del club (tabella `tactics`).
class Tactic {
  const Tactic({
    required this.id,
    required this.title,
    this.module,
    this.description = '',
    this.imagePath,
    this.localImage,
    this.board,
    this.team,
  });

  final String id;
  final String title;
  final String? module;
  final String description;
  final String? imagePath;

  /// Solo demo: immagine tenuta in memoria.
  final Uint8List? localImage;

  /// Lo schema disegnato sulla lavagna (null per le tattiche con sola immagine).
  final BoardState? board;

  /// Squadra della rosa usata sulla lavagna (milanac | futuro).
  final String? team;

  bool get hasImage => imagePath != null || localImage != null;
  bool get hasBoard => board != null;

  factory Tactic.fromMap(Map<String, dynamic> m) => Tactic(
    id: m['id'] as String,
    title: m['title'] as String,
    module: m['module'] as String?,
    description: (m['description'] as String?) ?? '',
    imagePath: m['image_path'] as String?,
    board: m['board'] == null
        ? null
        : BoardState.fromJson((m['board'] as Map).cast<String, dynamic>()),
    team: m['team'] as String?,
  );

  /// I campi da scrivere. Lavagna e squadra solo se ci sono: chi modifica il testo
  /// di uno schema non deve cancellarne il disegno.
  Map<String, dynamic> toMap() => {
    'title': title,
    'module': module,
    'description': description,
    if (board != null) 'board': board!.toJson(),
    if (team != null) 'team': team,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

abstract class TacticsRepository {
  Stream<List<Tactic>> watchAll();

  /// Crea o aggiorna; se [image] non è null carica la nuova immagine
  /// (JPEG, o PNG con [imageContentType] = image/png). I campi null della
  /// tattica (lavagna, squadra, immagine) restano come sono.
  Future<void> save(
    Tactic tactic, {
    Uint8List? image,
    String imageContentType = 'image/jpeg',
  });
  Future<void> delete(Tactic tactic);
  Future<String> imageUrl(Tactic tactic);
}

final tacticsRepositoryProvider = Provider<TacticsRepository>((ref) {
  if (AppConfig.isDemo) return DemoTacticsRepository();
  return _SupabaseTacticsRepository(ref);
});

final tacticsProvider = StreamProvider<List<Tactic>>((ref) {
  // Letti con i permessi dell'utente: si ricaricano al cambio di account.
  ref.watch(currentUserIdProvider);
  return ref.watch(tacticsRepositoryProvider).watchAll();
});

/// Indirizzo firmato dell'immagine (vale 6 ore): si butta quando nessuno lo mostra,
/// così la volta dopo se ne chiede uno nuovo invece di usarne uno scaduto.
final tacticImageUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) async {
      ref.watch(currentUserIdProvider);
      final repo = ref.watch(tacticsRepositoryProvider);
      return repo.imageUrl(Tactic(id: '', title: '', imagePath: path));
    });

/// Lo schema da salvare non c'è più (o non lo si può più modificare).
const _missing = AppError(
  'Schema non salvato: è stato eliminato o non hai più i permessi per modificarlo.',
);

class _SupabaseTacticsRepository implements TacticsRepository {
  _SupabaseTacticsRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Stream<List<Tactic>> watchAll() => _client
      .from('tactics')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Tactic.fromMap).toList());

  @override
  Future<void> save(
    Tactic t, {
    Uint8List? image,
    String imageContentType = 'image/jpeg',
  }) async {
    String? newPath;
    if (image != null) {
      final ext = imageContentType == 'image/png' ? 'png' : 'jpg';
      newPath = '${DateTime.now().microsecondsSinceEpoch}.$ext';
      await _client.storage
          .from(tacticsBucket)
          .uploadBinary(
            newPath,
            image,
            fileOptions: FileOptions(contentType: imageContentType),
          );
    }
    // L'immagine si scrive solo se è nuova: le altre restano come sono.
    final values = {...t.toMap(), 'image_path': ?newPath};
    try {
      if (t.id.isEmpty) {
        await _client.from('tactics').insert(values);
      } else {
        final rows = await _client
            .from('tactics')
            .update(values)
            .eq('id', t.id)
            .select('id');
        if (rows.isEmpty) throw _missing;
      }
    } catch (e, st) {
      // La riga non è cambiata: la nuova immagine resterebbe orfana.
      if (newPath != null) await _removeQuietly(newPath);
      Error.throwWithStackTrace(_readable(e), st);
    }
    // Solo ora che lo schema punta alla nuova immagine si toglie la vecchia.
    final old = t.imagePath;
    if (newPath != null && old != null) await _removeQuietly(old);
  }

  @override
  Future<void> delete(Tactic t) async {
    // Prima la riga: se non riesce, lo schema resta con la sua immagine.
    await _client.from('tactics').delete().eq('id', t.id);
    if (t.imagePath != null) await _removeQuietly(t.imagePath!);
  }

  /// Un file in meno nello storage; se non riesce resta un file orfano, non un errore.
  Future<void> _removeQuietly(String path) async {
    try {
      await _client.storage.from(tacticsBucket).remove([path]);
    } catch (_) {}
  }

  /// I limiti della tabella detti in italiano.
  static Object _readable(Object e) {
    if (e is PostgrestException && e.code == '23514') {
      return AppError(
        e.message.contains('board')
            ? 'Schema troppo grande per essere salvato: togli un po\' di heatmap e riprova.'
            : 'Schema non salvato: nome fino a 80 caratteri, spiegazione fino a 4000.',
      );
    }
    return e;
  }

  @override
  Future<String> imageUrl(Tactic t) => _client.storage
      .from(tacticsBucket)
      .createSignedUrl(t.imagePath!, 60 * 60 * 6);
}

class DemoTacticsRepository implements TacticsRepository {
  final _tactics = <Tactic>[
    const Tactic(
      id: 't1',
      title: 'Pressing alto dopo palla persa',
      module: '4-3-3',
      description:
          'Le due mezzali salgono sul portatore, il CDC copre la linea di passaggio '
          'centrale. Il terzino lato palla accorcia sull\'esterno. Se il pressing '
          'viene superato: tutti dietro la linea della palla.',
    ),
    const Tactic(
      id: 't2',
      title: 'Calcio d\'angolo a rientrare',
      module: 'Piazzati',
      description: 'Blocco sul primo palo, inserimento del DC sul secondo.',
    ),
    Tactic(
      id: 't3',
      title: 'Uscita dal basso',
      module: '4-3-3',
      team: 'milanac',
      description: 'Il portiere apre sul DC, il CDC si abbassa tra i centrali e i terzini salgono.',
      board: demoBoard(),
    ),
  ];
  final _changes = StreamController<void>.broadcast();
  var _next = 10;

  @override
  Stream<List<Tactic>> watchAll() async* {
    yield List.of(_tactics);
    yield* _changes.stream.map((_) => List.of(_tactics));
  }

  @override
  Future<void> save(
    Tactic t, {
    Uint8List? image,
    String imageContentType = 'image/jpeg',
  }) async {
    // Come il database: i campi null non cancellano quelli salvati.
    final i = _tactics.indexWhere((x) => x.id == t.id);
    if (t.id.isNotEmpty && i < 0) throw _missing;
    final old = i >= 0 ? _tactics[i] : null;
    final saved = Tactic(
      id: t.id.isEmpty ? 't${_next++}' : t.id,
      title: t.title,
      module: t.module,
      description: t.description,
      imagePath: t.imagePath ?? old?.imagePath,
      localImage: image ?? t.localImage ?? old?.localImage,
      board: t.board ?? old?.board,
      team: t.team ?? old?.team,
    );
    i >= 0 ? _tactics[i] = saved : _tactics.insert(0, saved);
    _changes.add(null);
  }

  @override
  Future<void> delete(Tactic t) async {
    _tactics.removeWhere((x) => x.id == t.id);
    _changes.add(null);
  }

  @override
  Future<String> imageUrl(Tactic t) async => '';
}
