import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import 'modules.dart';

abstract class FormationRepository {
  /// Formazione attuale della squadra (vuota se non ancora creata).
  Future<Formation> loadCurrent(Team team);

  /// Salva modulo e posti in un colpo solo; con l'id vuoto crea la formazione.
  Future<Formation> save(Formation formation);

  /// Pubblica la formazione: parte la notifica personale a ogni membro.
  Future<Formation> publish(Formation formation);
}

final formationRepositoryProvider = Provider<FormationRepository>((ref) {
  if (AppConfig.isDemo) return DemoFormationRepository();
  return _SupabaseFormationRepository(ref);
});

/// La formazione attuale della squadra. La pubblica il Direttivo da un altro telefono:
/// si rilegge a ogni apertura della pagina (rilascio automatico), quando entra un altro
/// account e quando la pagina lo chiede (ritorno in primo piano, trascinamento in giù).
final formationProvider = FutureProvider.autoDispose.family<Formation, Team>((
  ref,
  team,
) {
  if (ref.watch(currentUserIdProvider) == null) return Formation(team: team);
  return ref.watch(formationRepositoryProvider).loadCurrent(team);
});

/// I posti della formazione come li vuole `save_formation`
/// (`[{"slot_index", "x", "y", "label", "player_id"}]`, null = posto libero).
List<Map<String, Object?>> formationSlotsJson(Formation f) => [
  for (final (i, slot) in f.slots.indexed)
    {
      'slot_index': i,
      'x': slot.x,
      'y': slot.y,
      'label': slot.label,
      'player_id': f.players[i],
    },
];

class _SupabaseFormationRepository implements FormationRepository {
  _SupabaseFormationRepository(this._ref);
  final Ref _ref;

  @override
  Future<Formation> loadCurrent(Team team) async {
    final client = _ref.read(supabaseProvider);
    final row = await client
        .from('formations')
        .select(
          'id, module, published_at, updated_at, published_module, published_players, '
          'formation_slots(slot_index, player_id)',
        )
        .eq('is_current', true)
        .eq('team', team.name)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return Formation(team: team);
    DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
    return Formation(
      id: row['id'] as String,
      team: team,
      module: row['module'] as String,
      publishedAt: date(row['published_at']),
      updatedAt: date(row['updated_at']),
      publishedModule: row['published_module'] as String?,
      publishedPlayers: switch (row['published_players']) {
        final Map<String, dynamic> m => {
          for (final e in m.entries)
            if (e.value != null) int.parse(e.key): e.value as String,
        },
        _ => null,
      },
      players: {
        for (final s
            in (row['formation_slots'] as List).cast<Map<String, dynamic>>())
          if (s['player_id'] != null)
            (s['slot_index'] as num).toInt(): s['player_id'] as String,
      },
    );
  }

  @override
  Future<Formation> save(Formation f) async {
    final client = _ref.read(supabaseProvider);
    String id;
    try {
      // Modulo e posti in una sola transazione: se la rete cade a metà non resta
      // una bozza senza giocatori.
      id = await client.rpc(
        'save_formation',
        params: {
          'p_id': f.id.isEmpty ? null : f.id,
          'p_team': f.team.name,
          'p_module': f.module,
          'p_slots': formationSlotsJson(f),
        },
      ) as String;
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      // Database senza save_formation (migrazione non ancora applicata): come prima.
      id = await _saveInSteps(f);
    }
    return f.copyWith(id: id, updatedAt: DateTime.now().toUtc());
  }

  /// La strada di prima: formazione, poi i posti cancellati e riscritti.
  Future<String> _saveInSteps(Formation f) async {
    final client = _ref.read(supabaseProvider);
    final values = {
      'module': f.module,
      'team': f.team.name,
      'is_current': true,
      'updated_by': client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final id = f.id.isEmpty
        ? (await client
                  .from('formations')
                  .insert(values)
                  .select('id')
                  .single())['id']
              as String
        : f.id;
    if (f.id.isNotEmpty) {
      await client.from('formations').update(values).eq('id', id);
    }
    await client.from('formation_slots').delete().eq('formation_id', id);
    await client.from('formation_slots').insert([
      for (final slot in formationSlotsJson(f)) {...slot, 'formation_id': id},
    ]);
    return id;
  }

  @override
  Future<Formation> publish(Formation f) async {
    final saved = f.id.isEmpty ? await save(f) : f;
    final client = _ref.read(supabaseProvider);
    final now = DateTime.now().toUtc();
    await client
        .from('formations')
        .update({
          'published_at': now.toIso8601String(),
          'published_by': client.auth.currentUser?.id,
          'published_module': saved.module,
          'published_players': {
            for (final e in saved.players.entries) '${e.key}': e.value,
          },
        })
        .eq('id', saved.id);
    return saved.copyWith(
      publishedAt: now,
      updatedAt: now,
      publishedModule: saved.module,
      publishedPlayers: Map.of(saved.players),
    );
  }
}

class DemoFormationRepository implements FormationRepository {
  final _current = <Team, Formation>{
    Team.milanac: const Formation(
      id: 'demo',
      players: {0: 'p4', 2: 'p3', 6: 'demo', 9: 'p2'},
    ),
    Team.futuro: const Formation(
      id: 'demo-futuro',
      team: Team.futuro,
      module: '4-4-2',
      players: {0: 'p4', 6: 'p6'},
    ),
  };

  @override
  Future<Formation> loadCurrent(Team team) async =>
      _current[team] ?? Formation(team: team);

  @override
  Future<Formation> save(Formation f) async => _current[f.team] = f.copyWith(
    id: 'demo-${f.team.name}',
    updatedAt: DateTime.now().toUtc(),
  );

  @override
  Future<Formation> publish(Formation f) async {
    final now = DateTime.now().toUtc();
    return _current[f.team] = f.copyWith(
      id: 'demo-${f.team.name}',
      publishedAt: now,
      updatedAt: now,
      publishedModule: f.module,
      publishedPlayers: Map.of(f.players),
    );
  }
}
