import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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
  return SupabaseFormationRepository(ref);
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

/// Chi batte le palle inattive nell'ultima formazione pubblicata della squadra: ruolo →
/// id del giocatore (sempre un titolare di quella formazione; vuoto se non è ancora
/// pubblicata o se il Direttivo non li ha scelti). Per chi li usa fuori dalla
/// Formazione, come gli schemi da palla inattiva della lavagna; si rilegge con
/// [formationProvider].
final publishedSetPiecesProvider = FutureProvider.autoDispose
    .family<Map<SetPiece, String>, Team>((ref, team) async {
      final formation = await ref.watch(formationProvider(team).future);
      return formation.isPublished
          ? formation.publishedView.setPieces
          : const <SetPiece, String>{};
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

/// La formazione da una riga di `formations` (con i suoi `formation_slots`). I battitori
/// di chi non è più tra i titolari (account eliminato) non si tengono.
Formation formationFromRow(Map<String, dynamic> row, Team team) {
  DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
  final players = {
    for (final s
        in (row['formation_slots'] as List).cast<Map<String, dynamic>>())
      if (s['player_id'] != null)
        (s['slot_index'] as num).toInt(): s['player_id'] as String,
  };
  final publishedPlayers = switch (row['published_players']) {
    final Map<String, dynamic> m => {
      for (final e in m.entries)
        if (e.value != null) int.parse(e.key): e.value as String,
    },
    _ => null,
  };
  final publishedSetPieces = row['published_set_pieces'];
  return Formation(
    id: row['id'] as String,
    team: team,
    module: row['module'] as String,
    publishedAt: date(row['published_at']),
    updatedAt: date(row['updated_at']),
    publishedModule: row['published_module'] as String?,
    publishedPlayers: publishedPlayers,
    players: players,
    setPieces: setPiecesAmong(
      parseSetPieces(row['set_pieces']),
      players.values,
    ),
    publishedSetPieces: publishedSetPieces == null
        ? null
        : setPiecesAmong(
            parseSetPieces(publishedSetPieces),
            publishedPlayers?.values ?? const [],
          ),
  );
}

class SupabaseFormationRepository implements FormationRepository {
  SupabaseFormationRepository(this._ref);
  final Ref _ref;

  static const _columns =
      'id, module, published_at, updated_at, published_module, published_players, '
      'formation_slots(slot_index, player_id)';

  @override
  Future<Formation> loadCurrent(Team team) async {
    final client = _ref.read(supabaseProvider);
    Future<Map<String, dynamic>?> current(String columns) => client
        .from('formations')
        .select(columns)
        .eq('is_current', true)
        .eq('team', team.name)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    Map<String, dynamic>? row;
    try {
      row = await current('$_columns, set_pieces, published_set_pieces');
    } on PostgrestException catch (e) {
      // Database senza i battitori (migrazione 0035 non ancora applicata): il resto sì.
      if (e.code != '42703') rethrow;
      row = await current(_columns);
    }
    if (row == null) return Formation(team: team);
    return formationFromRow(row, team);
  }

  @override
  Future<Formation> save(Formation f) async {
    final client = _ref.read(supabaseProvider);
    // Modulo, posti e battitori in una sola transazione: se la rete cade a metà non
    // resta una bozza senza giocatori.
    Future<String> rpc({required bool withSetPieces}) async => await client.rpc(
      'save_formation',
      params: {
        'p_id': f.id.isEmpty ? null : f.id,
        'p_team': f.team.name,
        'p_module': f.module,
        'p_slots': formationSlotsJson(f),
        if (withSetPieces)
          'p_set_pieces': setPiecesJson(
            setPiecesAmong(f.setPieces, f.players.values),
          ),
      },
    ) as String;
    String id;
    try {
      id = await rpc(withSetPieces: true);
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      try {
        // Database senza i battitori (migrazione 0035 non ancora applicata).
        id = await rpc(withSetPieces: false);
      } catch (e) {
        if (!isMissingFunction(e)) rethrow;
        // Database senza save_formation (migrazione non ancora applicata): come prima.
        id = await _saveInSteps(f);
      }
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
    // Solo battitori in campo (il database toglie comunque gli altri).
    final setPieces = setPiecesAmong(saved.setPieces, saved.players.values);
    Future<List<Map<String, dynamic>>> update({
      required bool withSetPieces,
    }) => client
        .from('formations')
        .update({
          // L'ora vera la fissa il server (migrazione 0025): si usa quella che torna.
          'published_at': DateTime.now().toUtc().toIso8601String(),
          'published_by': client.auth.currentUser?.id,
          'published_module': saved.module,
          'published_players': {
            for (final e in saved.players.entries) '${e.key}': e.value,
          },
          if (withSetPieces) 'published_set_pieces': setPiecesJson(setPieces),
        })
        .eq('id', saved.id)
        .select('published_at');
    List<Map<String, dynamic>> rows;
    try {
      rows = await update(withSetPieces: true);
    } on PostgrestException catch (e) {
      // Database senza i battitori (migrazione 0035 non ancora applicata): il resto sì.
      if (e.code != 'PGRST204') rethrow;
      rows = await update(withSetPieces: false);
    }
    // Nessuna riga cambiata (formazione eliminata da un altro telefono, permessi
    // cambiati): prima risultava pubblicata senza esserlo.
    if (rows.isEmpty) {
      throw const AppError(
        'Formazione non trovata: riapri la pagina e pubblica di nuovo.',
      );
    }
    final publishedAt = DateTime.parse(rows.first['published_at'] as String);
    return saved.copyWith(
      publishedAt: publishedAt,
      updatedAt: publishedAt,
      publishedModule: saved.module,
      publishedPlayers: Map.of(saved.players),
      setPieces: setPieces,
      publishedSetPieces: setPieces,
    );
  }
}

class DemoFormationRepository implements FormationRepository {
  // Rigori e angoli da destra a Rossi, punizioni e angoli da sinistra al Demo; nel
  // Futuro Verdi batte tutto tranne gli angoli da destra (ancora da scegliere).
  final _current = <Team, Formation>{
    Team.milanac: const Formation(
      id: 'demo',
      players: {0: 'p4', 2: 'p3', 6: 'demo', 9: 'p2'},
      setPieces: {
        SetPiece.rigori: 'p2',
        SetPiece.punizioni: 'demo',
        SetPiece.angoliSinistra: 'demo',
        SetPiece.angoliDestra: 'p2',
      },
    ),
    Team.futuro: const Formation(
      id: 'demo-futuro',
      team: Team.futuro,
      module: '4-4-2',
      players: {0: 'p4', 6: 'p6'},
      setPieces: {
        SetPiece.rigori: 'p6',
        SetPiece.punizioni: 'p6',
        SetPiece.angoliSinistra: 'p6',
      },
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
    // Come il database: solo battitori in campo.
    final setPieces = setPiecesAmong(f.setPieces, f.players.values);
    return _current[f.team] = f.copyWith(
      id: 'demo-${f.team.name}',
      publishedAt: now,
      updatedAt: now,
      publishedModule: f.module,
      publishedPlayers: Map.of(f.players),
      setPieces: setPieces,
      publishedSetPieces: setPieces,
    );
  }
}
