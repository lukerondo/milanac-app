import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import 'match.dart';

const mediaBucket = 'match-media';

abstract class MatchesRepository {
  Stream<List<ClubMatch>> watchAll();

  /// Crea la partita se [ClubMatch.id] è vuoto, altrimenti la aggiorna. Restituisce l'id.
  Future<String> save(ClubMatch match);

  /// Il server non ha ancora i minuti dei gol (migrazione 0027): le partite si salvano
  /// senza. Diventa vero al primo salvataggio rifiutato per questo.
  bool get timelineMissing;
  Future<void> delete(String id);

  /// Foto, clip e link di tutte le partite.
  Stream<List<MatchMedia>> watchAllMedia();
  Future<void> addLink(String matchId, String url, {String? caption});
  Future<void> uploadMedia(
    String matchId, {
    required MediaType type,
    required Uint8List bytes,
    required String extension,
    int? durationS,
    String? caption,
  });
  Future<void> deleteMedia(MatchMedia media);

  /// URL temporaneo per vedere un file privato dello storage.
  Future<String> mediaUrl(MatchMedia media);
}

final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  if (AppConfig.isDemo) return DemoMatchesRepository();
  return SupabaseMatchesRepository(ref);
});

final matchesProvider = StreamProvider<List<ClubMatch>>((ref) {
  // Al cambio di account si ricarica con i permessi del nuovo utente.
  ref.watch(currentUserIdProvider);
  return ref.watch(matchesRepositoryProvider).watchAll();
});

/// I media di tutte le partite: un solo canale in tempo reale per tutte le schede
/// (prima ne apriva uno ogni partita in elenco) e, senza filtro sul server,
/// arrivano anche le eliminazioni.
final allMatchMediaProvider = StreamProvider<List<MatchMedia>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(matchesRepositoryProvider).watchAllMedia();
});

/// I media di una partita (dallo stream condiviso).
final matchMediaProvider =
    Provider.family<AsyncValue<List<MatchMedia>>, String>(
      (ref, matchId) => ref
          .watch(allMatchMediaProvider)
          .whenData(
            (all) => [
              for (final m in all)
                if (m.matchId == matchId) m,
            ],
          ),
    );

/// Scrive la partita con [write]. Un database prima della 0027 non ha la colonna dei
/// minuti dei gol (PostgREST risponde PGRST204): si riscrive senza, e da lì in poi non
/// la si manda più. Restituisce l'id e se la colonna manca.
Future<(String, bool)> writeMatch(
  Map<String, dynamic> map,
  Future<String> Function(Map<String, dynamic> map) write, {
  bool timelineMissing = false,
}) async {
  if (timelineMissing) return (await write(map..remove('timeline')), true);
  try {
    return (await write(map), false);
  } on PostgrestException catch (e) {
    if (e.code != 'PGRST204') rethrow;
    return (await write(map..remove('timeline')), true);
  }
}

class SupabaseMatchesRepository implements MatchesRepository {
  SupabaseMatchesRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  /// Dalla più recente: lo stream ordina solo per orario, le partite della stessa sera
  /// le mette in fila [newestMatchFirst].
  @override
  Stream<List<ClubMatch>> watchAll() => _client
      .from('matches')
      .stream(primaryKey: ['id'])
      .order('played_at', ascending: false)
      .map(
        (rows) => rows.map(ClubMatch.fromMap).toList()..sort(newestMatchFirst),
      );

  @override
  bool timelineMissing = false;

  @override
  Future<String> save(ClubMatch m) async {
    final (id, missing) = await writeMatch(
      m.toMap(),
      (map) => _write(m.id, map),
      timelineMissing: timelineMissing,
    );
    timelineMissing = missing;
    return id;
  }

  Future<String> _write(String id, Map<String, dynamic> map) async {
    if (id.isEmpty) {
      final row = await _client
          .from('matches')
          .insert(map)
          .select('id')
          .single();
      return row['id'] as String;
    }
    await _client.from('matches').update(map).eq('id', id);
    return id;
  }

  @override
  Future<void> delete(String id) async {
    final media = await _client
        .from('match_media')
        .select('storage_path')
        .eq('match_id', id);
    final paths = [
      for (final r in media)
        if (r['storage_path'] != null) r['storage_path'] as String,
    ];
    // Prima il database (i media della partita se ne vanno con lei), poi i file: se la
    // rete cade a metà resta al più un file orfano, mai un media che punta a un file
    // cancellato. I file non si aspettano: la partita è già sparita (in tempo reale
    // anche dalla pagina aperta) e la pagina si chiude subito.
    await _client.from('matches').delete().eq('id', id);
    unawaited(_removeQuietly(paths));
  }

  /// File in meno nello storage; se non riesce restano file orfani, non un errore.
  Future<void> _removeQuietly(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(mediaBucket).remove(paths);
    } catch (_) {}
  }

  @override
  Stream<List<MatchMedia>> watchAllMedia() => _client
      .from('match_media')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map(MatchMedia.fromMap).toList());

  @override
  Future<void> addLink(String matchId, String url, {String? caption}) async {
    await _client.from('match_media').insert({
      'match_id': matchId,
      'type': MediaType.link.name,
      'url': url,
      'caption': caption,
      'uploaded_by': _client.auth.currentUser?.id,
    });
  }

  @override
  Future<void> uploadMedia(
    String matchId, {
    required MediaType type,
    required Uint8List bytes,
    required String extension,
    int? durationS,
    String? caption,
  }) async {
    final path = '$matchId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage
        .from(mediaBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: type == MediaType.video ? 'video/mp4' : 'image/jpeg',
          ),
        );
    try {
      await _client.from('match_media').insert({
        'match_id': matchId,
        'type': type.name,
        'storage_path': path,
        'duration_s': durationS,
        'caption': caption,
        'uploaded_by': _client.auth.currentUser?.id,
      });
    } on PostgrestException {
      // Il database l'ha rifiutato: il file resterebbe orfano. Con la rete caduta invece
      // non si sa se la riga c'è, e il file resta.
      await _removeQuietly([path]);
      rethrow;
    }
  }

  @override
  Future<void> deleteMedia(MatchMedia media) async {
    // Prima la riga, poi il file (vedi [delete]).
    await _client.from('match_media').delete().eq('id', media.id);
    await _removeQuietly([?media.storagePath]);
  }

  @override
  Future<String> mediaUrl(MatchMedia media) => _client.storage
      .from(mediaBucket)
      .createSignedUrl(media.storagePath!, 60 * 60);
}

class DemoMatchesRepository implements MatchesRepository {
  DemoMatchesRepository() {
    // Ore italiane, come le partite lette dal server.
    final today = italianClock(DateTime.now());
    DateTime ago(int d) =>
        DateTime.utc(today.year, today.month, today.day - d, 21, 30);
    // Inserite a fine partita, come fa il Direttivo.
    DateTime insertedAfter(int d) =>
        fromItalianClock(ago(d)).add(const Duration(hours: 1));
    _matches.addAll([
      ClubMatch(
        id: 'm1',
        kind: MatchKind.torneo,
        tournamentId: 'tr1',
        competition: 'FVPA Serie B – 2ª giornata',
        opponent: 'Dinamo Pixel',
        playedAt: ago(5),
        createdAt: insertedAfter(5),
        goalsFor: 3,
        goalsAgainst: 1,
        scorers: 'Rossi (2), Bianchi',
        notes: 'Rimonta nel secondo tempo!',
        goalkeeperId: 'p4',
        timeline: const [
          MatchGoal(minute: 18, ours: false),
          MatchGoal(minute: 52, ours: true, scorer: 'Rossi'),
          MatchGoal(minute: 67, ours: true, scorer: 'Rossi'),
          MatchGoal(minute: 88, ours: true, scorer: 'Bianchi'),
        ],
      ),
      ClubMatch(
        id: 'm2',
        team: Team.futuro,
        kind: MatchKind.amichevole,
        opponent: 'Real Brianza',
        playedAt: ago(9),
        createdAt: insertedAfter(9),
        home: false,
        goalsFor: 2,
        goalsAgainst: 2,
        scorers: 'Rossi, Neri',
      ),
      ClubMatch(
        id: 'm3',
        kind: MatchKind.torneo,
        competition: 'FVPA Serie B – 1ª giornata',
        opponent: 'Sporting Joypad',
        playedAt: ago(12),
        createdAt: insertedAfter(12),
        goalsFor: 0,
        goalsAgainst: 1,
      ),
    ]);
    _media.add(
      const MatchMedia(
        id: 'x1',
        matchId: 'm1',
        type: MediaType.link,
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        caption: 'Highlights completi',
      ),
    );
  }

  final _matches = <ClubMatch>[];
  final _media = <MatchMedia>[];
  final _matchesCtrl = StreamController<List<ClubMatch>>.broadcast();
  final _mediaCtrl = StreamController<void>.broadcast();
  var _nextId = 100;
  DateTime? _lastInsert;

  List<ClubMatch> get _sorted => List.of(_matches)..sort(newestMatchFirst);

  /// L'ora di inserimento, come `created_at` del database: sempre successiva alla
  /// precedente (due salvataggi di fila possono cadere nello stesso istante).
  DateTime _insertedNow() {
    final now = DateTime.now().toUtc();
    final last = _lastInsert;
    return _lastInsert = last != null && !now.isAfter(last)
        ? last.add(const Duration(microseconds: 1))
        : now;
  }

  @override
  Stream<List<ClubMatch>> watchAll() async* {
    yield _sorted;
    yield* _matchesCtrl.stream;
  }

  @override
  bool get timelineMissing => false;

  @override
  Future<String> save(ClubMatch m) async {
    final id = m.id.isEmpty ? 'm${_nextId++}' : m.id;
    final old = _matches.where((x) => x.id == id).firstOrNull;
    _matches.removeWhere((x) => x.id == id);
    _matches.add(
      ClubMatch(
        id: id,
        kind: m.kind,
        opponent: m.opponent,
        playedAt: m.playedAt,
        createdAt: old?.createdAt ?? _insertedNow(),
        competition: m.competition,
        home: m.home,
        goalsFor: m.goalsFor,
        goalsAgainst: m.goalsAgainst,
        scorers: m.scorers,
        notes: m.notes,
        team: m.team,
        tournamentId: m.tournamentId,
        goalkeeperId: m.goalkeeperId,
        timeline: sortedGoals(m.timeline),
      ),
    );
    _matchesCtrl.add(_sorted);
    return id;
  }

  @override
  Future<void> delete(String id) async {
    _matches.removeWhere((x) => x.id == id);
    _media.removeWhere((x) => x.matchId == id);
    _matchesCtrl.add(_sorted);
    _mediaCtrl.add(null);
  }

  @override
  Stream<List<MatchMedia>> watchAllMedia() async* {
    yield List.of(_media);
    yield* _mediaCtrl.stream.map((_) => List.of(_media));
  }

  @override
  Future<void> addLink(String matchId, String url, {String? caption}) async {
    _media.add(
      MatchMedia(
        id: 'x${_nextId++}',
        matchId: matchId,
        type: MediaType.link,
        url: url,
        caption: caption,
      ),
    );
    _mediaCtrl.add(null);
  }

  @override
  Future<void> uploadMedia(
    String matchId, {
    required MediaType type,
    required Uint8List bytes,
    required String extension,
    int? durationS,
    String? caption,
  }) async {
    _media.add(
      MatchMedia(
        id: 'x${_nextId++}',
        matchId: matchId,
        type: type,
        storagePath: 'demo.$extension',
        durationS: durationS,
        caption: caption,
        localBytes: bytes,
      ),
    );
    _mediaCtrl.add(null);
  }

  @override
  Future<void> deleteMedia(MatchMedia media) async {
    _media.removeWhere((m) => m.id == media.id);
    _mediaCtrl.add(null);
  }

  @override
  Future<String> mediaUrl(MatchMedia media) async => '';
}
