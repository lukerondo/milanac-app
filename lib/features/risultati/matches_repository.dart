import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/teams.dart';
import 'match.dart';

const mediaBucket = 'match-media';

abstract class MatchesRepository {
  Stream<List<ClubMatch>> watchAll();

  /// Crea la partita se [ClubMatch.id] è vuoto, altrimenti la aggiorna. Restituisce l'id.
  Future<String> save(ClubMatch match);
  Future<void> delete(String id);

  Stream<List<MatchMedia>> watchMedia(String matchId);
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
  return _SupabaseMatchesRepository(ref);
});

final matchesProvider = StreamProvider<List<ClubMatch>>(
  (ref) => ref.watch(matchesRepositoryProvider).watchAll(),
);

final matchMediaProvider = StreamProvider.family<List<MatchMedia>, String>(
  (ref, matchId) => ref.watch(matchesRepositoryProvider).watchMedia(matchId),
);

class _SupabaseMatchesRepository implements MatchesRepository {
  _SupabaseMatchesRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Stream<List<ClubMatch>> watchAll() => _client
      .from('matches')
      .stream(primaryKey: ['id'])
      .order('played_at', ascending: false)
      .map((rows) => rows.map(ClubMatch.fromMap).toList());

  @override
  Future<String> save(ClubMatch m) async {
    if (m.id.isEmpty) {
      final row = await _client
          .from('matches')
          .insert(m.toMap())
          .select('id')
          .single();
      return row['id'] as String;
    }
    await _client.from('matches').update(m.toMap()).eq('id', m.id);
    return m.id;
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
    if (paths.isNotEmpty) await _client.storage.from(mediaBucket).remove(paths);
    await _client.from('matches').delete().eq('id', id);
  }

  @override
  Stream<List<MatchMedia>> watchMedia(String matchId) => _client
      .from('match_media')
      .stream(primaryKey: ['id'])
      .eq('match_id', matchId)
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
    await _client.from('match_media').insert({
      'match_id': matchId,
      'type': type.name,
      'storage_path': path,
      'duration_s': durationS,
      'caption': caption,
      'uploaded_by': _client.auth.currentUser?.id,
    });
  }

  @override
  Future<void> deleteMedia(MatchMedia media) async {
    if (media.storagePath != null) {
      await _client.storage.from(mediaBucket).remove([media.storagePath!]);
    }
    await _client.from('match_media').delete().eq('id', media.id);
  }

  @override
  Future<String> mediaUrl(MatchMedia media) => _client.storage
      .from(mediaBucket)
      .createSignedUrl(media.storagePath!, 60 * 60);
}

class DemoMatchesRepository implements MatchesRepository {
  DemoMatchesRepository() {
    final now = DateTime.now();
    DateTime ago(int d) => DateTime(now.year, now.month, now.day - d, 21, 30);
    _matches.addAll([
      ClubMatch(
        id: 'm1',
        kind: MatchKind.torneo,
        tournamentId: 'tr1',
        competition: 'FVPA Serie B – 2ª giornata',
        opponent: 'Dinamo Pixel',
        playedAt: ago(5),
        goalsFor: 3,
        goalsAgainst: 1,
        scorers: 'Rossi (2), Bianchi',
        notes: 'Rimonta nel secondo tempo!',
        goalkeeperId: 'p4',
      ),
      ClubMatch(
        id: 'm2',
        team: Team.futuro,
        kind: MatchKind.amichevole,
        opponent: 'Real Brianza',
        playedAt: ago(9),
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

  List<ClubMatch> get _sorted =>
      List.of(_matches)..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  @override
  Stream<List<ClubMatch>> watchAll() async* {
    yield _sorted;
    yield* _matchesCtrl.stream;
  }

  @override
  Future<String> save(ClubMatch m) async {
    final id = m.id.isEmpty ? 'm${_nextId++}' : m.id;
    _matches.removeWhere((x) => x.id == id);
    _matches.add(
      ClubMatch(
        id: id,
        kind: m.kind,
        opponent: m.opponent,
        playedAt: m.playedAt,
        competition: m.competition,
        home: m.home,
        goalsFor: m.goalsFor,
        goalsAgainst: m.goalsAgainst,
        scorers: m.scorers,
        notes: m.notes,
        team: m.team,
        tournamentId: m.tournamentId,
        goalkeeperId: m.goalkeeperId,
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

  List<MatchMedia> _mediaOf(String matchId) =>
      _media.where((m) => m.matchId == matchId).toList();

  @override
  Stream<List<MatchMedia>> watchMedia(String matchId) async* {
    yield _mediaOf(matchId);
    yield* _mediaCtrl.stream.map((_) => _mediaOf(matchId));
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
