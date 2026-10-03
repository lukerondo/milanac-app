import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import 'trophy.dart';

const trophiesBucket = 'trophies';

abstract class TrophiesRepository {
  /// Stagioni dalla più recente.
  Future<List<Season>> seasons();

  /// Restituisce la stagione con quell'etichetta, creandola se non esiste.
  Future<Season> ensureSeason(String label);
  Future<List<Trophy>> trophies(String seasonId);

  /// Crea o aggiorna il trofeo; se [image] non è null carica la nuova immagine PNG.
  Future<void> save(Trophy trophy, {Uint8List? image});
  Future<void> delete(Trophy trophy);
  Future<String> imageUrl(Trophy trophy);
}

final trophiesRepositoryProvider = Provider<TrophiesRepository>((ref) {
  if (AppConfig.isDemo) return DemoTrophiesRepository();
  return _SupabaseTrophiesRepository(ref);
});

final seasonsProvider = FutureProvider<List<Season>>(
  (ref) => ref.watch(trophiesRepositoryProvider).seasons(),
);

final trophiesProvider = FutureProvider.family<List<Trophy>, String>(
  (ref, seasonId) => ref.watch(trophiesRepositoryProvider).trophies(seasonId),
);

final trophyImageUrlProvider = FutureProvider.family<String, Trophy>(
  (ref, t) => ref.watch(trophiesRepositoryProvider).imageUrl(t),
);

class _SupabaseTrophiesRepository implements TrophiesRepository {
  _SupabaseTrophiesRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Future<List<Season>> seasons() async {
    final rows = await _client
        .from('seasons')
        .select()
        .order('label', ascending: false);
    return rows.map(Season.fromMap).toList();
  }

  @override
  Future<Season> ensureSeason(String label) async {
    final row = await _client
        .from('seasons')
        .upsert({'label': label}, onConflict: 'label')
        .select()
        .single();
    return Season.fromMap(row);
  }

  @override
  Future<List<Trophy>> trophies(String seasonId) async {
    final rows = await _client
        .from('trophies')
        .select()
        .eq('season_id', seasonId)
        .order('won_on', ascending: true, nullsFirst: false);
    return rows.map(Trophy.fromMap).toList();
  }

  @override
  Future<void> save(Trophy t, {Uint8List? image}) async {
    var imagePath = t.imagePath;
    if (image != null) {
      final path = '${t.seasonId}/${DateTime.now().microsecondsSinceEpoch}.png';
      await _client.storage
          .from(trophiesBucket)
          .uploadBinary(
            path,
            image,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
      if (t.imagePath != null) {
        await _client.storage.from(trophiesBucket).remove([t.imagePath!]);
      }
      imagePath = path;
    }
    final values = {...t.toMap(), 'image_path': imagePath};
    if (t.id.isEmpty) {
      await _client.from('trophies').insert(values);
    } else {
      await _client.from('trophies').update(values).eq('id', t.id);
    }
  }

  @override
  Future<void> delete(Trophy t) async {
    if (t.imagePath != null) {
      await _client.storage.from(trophiesBucket).remove([t.imagePath!]);
    }
    await _client.from('trophies').delete().eq('id', t.id);
  }

  @override
  Future<String> imageUrl(Trophy t) => _client.storage
      .from(trophiesBucket)
      .createSignedUrl(t.imagePath!, 60 * 60 * 6);
}

class DemoTrophiesRepository implements TrophiesRepository {
  final _seasons = <Season>[
    const Season(id: 's26', label: '2026/27'),
    const Season(id: 's25', label: '2025/26'),
  ];

  final _trophies = <Trophy>[
    Trophy(
      id: 't1',
      seasonId: 's25',
      name: 'Campioni FVPA Serie C',
      competition: 'FVPA',
      wonOn: DateTime(2026, 3, 22),
      shape: TrophyShape.scudetto,
      description: 'Promozione in Serie B con 2 giornate di anticipo.',
    ),
    Trophy(
      id: 't2',
      seasonId: 's25',
      name: 'Coppa FVPA',
      competition: 'FVPA',
      wonOn: DateTime(2026, 5, 10),
      shape: TrophyShape.coppa,
      description: 'Finale vinta 3-2 ai supplementari.',
    ),
    Trophy(
      id: 't3',
      seasonId: 's25',
      name: 'Torneo di Natale',
      competition: 'Amichevole',
      wonOn: DateTime(2025, 12, 20),
      shape: TrophyShape.targa,
    ),
    Trophy(
      id: 't4',
      seasonId: 's25',
      name: 'Miglior attacco',
      wonOn: DateTime(2026, 6, 1),
      shape: TrophyShape.medaglia,
    ),
    Trophy(
      id: 't5',
      seasonId: 's25',
      name: 'MVP Stagione – Rossi',
      wonOn: DateTime(2026, 6, 2),
      shape: TrophyShape.stella,
    ),
  ];
  var _nextId = 100;

  @override
  Future<List<Season>> seasons() async => List.of(_seasons);

  @override
  Future<Season> ensureSeason(String label) async {
    final existing = _seasons.where((s) => s.label == label).firstOrNull;
    if (existing != null) return existing;
    final s = Season(id: 's${_nextId++}', label: label);
    _seasons
      ..add(s)
      ..sort((a, b) => b.label.compareTo(a.label));
    return s;
  }

  @override
  Future<List<Trophy>> trophies(String seasonId) async =>
      _trophies.where((t) => t.seasonId == seasonId).toList()..sort(
        (a, b) =>
            (a.wonOn ?? DateTime(9999)).compareTo(b.wonOn ?? DateTime(9999)),
      );

  @override
  Future<void> save(Trophy t, {Uint8List? image}) async {
    final id = t.id.isEmpty ? 't${_nextId++}' : t.id;
    final old = _trophies.where((x) => x.id == id).firstOrNull;
    _trophies.removeWhere((x) => x.id == id);
    _trophies.add(
      Trophy(
        id: id,
        seasonId: t.seasonId,
        name: t.name,
        competition: t.competition,
        wonOn: t.wonOn,
        shape: t.shape,
        description: t.description,
        localBytes: image ?? old?.localBytes,
      ),
    );
  }

  @override
  Future<void> delete(Trophy t) async =>
      _trophies.removeWhere((x) => x.id == t.id);

  @override
  Future<String> imageUrl(Trophy t) async => '';
}
