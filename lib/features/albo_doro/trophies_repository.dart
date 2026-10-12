import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
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
  return SupabaseTrophiesRepository(ref);
});

/// Stagioni e trofei non arrivano in tempo reale (li cambia il Direttivo da un altro
/// telefono): si rileggono a ogni apertura dell'Albo d'oro (rilascio automatico) e al
/// ritorno in primo piano.
final seasonsProvider = FutureProvider.autoDispose<List<Season>>((ref) {
  // Al cambio di account si ricarica con i permessi del nuovo utente.
  ref.watch(currentUserIdProvider);
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.watch(trophiesRepositoryProvider).seasons();
});

final trophiesProvider = FutureProvider.autoDispose
    .family<List<Trophy>, String>((ref, seasonId) {
      ref.watch(currentUserIdProvider);
      final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
      ref.onDispose(lifecycle.dispose);
      return ref.watch(trophiesRepositoryProvider).trophies(seasonId);
    });

/// URL firmato della foto del trofeo. Vale 6 ore: si riusa per 5, poi (quando nessuno
/// lo mostra più) se ne chiede uno nuovo.
final trophyImageUrlProvider = FutureProvider.autoDispose
    .family<String, Trophy>((ref, t) async {
      final keep = ref.keepAlive();
      final timer = Timer(const Duration(hours: 5), keep.close);
      ref.onDispose(timer.cancel);
      try {
        return await ref.watch(trophiesRepositoryProvider).imageUrl(t);
      } catch (_) {
        keep.close(); // un errore non resta in memoria
        rethrow;
      }
    });

class SupabaseTrophiesRepository implements TrophiesRepository {
  SupabaseTrophiesRepository(this._ref);
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

  /// Prima la foto nuova, poi il trofeo che la usa, e solo alla fine via la foto di
  /// prima: se la rete cade a metà resta al più un file orfano, mai un trofeo che punta
  /// a una foto cancellata.
  @override
  Future<void> save(Trophy t, {Uint8List? image}) async {
    String? newPath;
    if (image != null) {
      newPath = '${t.seasonId}/${DateTime.now().microsecondsSinceEpoch}.png';
      await _client.storage
          .from(trophiesBucket)
          .uploadBinary(
            newPath,
            image,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
    }
    final values = {...t.toMap(), 'image_path': newPath ?? t.imagePath};
    try {
      if (t.id.isEmpty) {
        await _client.from('trophies').insert(values);
      } else {
        await _client.from('trophies').update(values).eq('id', t.id);
      }
    } on PostgrestException {
      // Il trofeo non è cambiato: la foto nuova resterebbe orfana. (Con la rete caduta
      // non si sa se l'ha presa, e il file resta.)
      if (newPath != null) await _removeQuietly(newPath);
      rethrow;
    }
    final old = t.imagePath;
    if (newPath != null && old != null) await _removeQuietly(old);
  }

  @override
  Future<void> delete(Trophy t) async {
    // Prima la riga: se non riesce, il trofeo resta con la sua foto.
    await _client.from('trophies').delete().eq('id', t.id);
    if (t.imagePath != null) await _removeQuietly(t.imagePath!);
  }

  /// Un file in meno nello storage; se non riesce resta un file orfano, non un errore.
  Future<void> _removeQuietly(String path) async {
    try {
      await _client.storage.from(trophiesBucket).remove([path]);
    } catch (_) {}
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
