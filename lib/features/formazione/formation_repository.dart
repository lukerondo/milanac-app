import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import 'modules.dart';

abstract class FormationRepository {
  Future<Formation> loadCurrent();
  Future<Formation> save(Formation formation);

  /// Pubblica la formazione: parte la notifica personale a ogni membro.
  Future<Formation> publish(Formation formation);
}

final formationRepositoryProvider = Provider<FormationRepository>((ref) {
  if (AppConfig.isDemo) return DemoFormationRepository();
  return _SupabaseFormationRepository(ref);
});

final formationProvider = FutureProvider<Formation>(
  (ref) => ref.watch(formationRepositoryProvider).loadCurrent(),
);

class _SupabaseFormationRepository implements FormationRepository {
  _SupabaseFormationRepository(this._ref);
  final Ref _ref;

  @override
  Future<Formation> loadCurrent() async {
    final client = _ref.read(supabaseProvider);
    final row = await client
        .from('formations')
        .select(
          'id, module, published_at, updated_at, formation_slots(slot_index, player_id)',
        )
        .eq('is_current', true)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return const Formation();
    DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
    return Formation(
      id: row['id'] as String,
      module: row['module'] as String,
      publishedAt: date(row['published_at']),
      updatedAt: date(row['updated_at']),
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
    final values = {
      'module': f.module,
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
      for (final (i, slot) in f.slots.indexed)
        {
          'formation_id': id,
          'slot_index': i,
          'x': slot.x,
          'y': slot.y,
          'label': slot.label,
          'player_id': f.players[i],
        },
    ]);
    return f.copyWith(id: id, updatedAt: DateTime.now().toUtc());
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
        })
        .eq('id', saved.id);
    return saved.copyWith(publishedAt: now, updatedAt: now);
  }
}

class DemoFormationRepository implements FormationRepository {
  Formation _current = const Formation(
    id: 'demo',
    players: {0: 'p4', 2: 'p3', 6: 'demo', 9: 'p2'},
  );

  @override
  Future<Formation> loadCurrent() async => _current;

  @override
  Future<Formation> save(Formation f) async =>
      _current = f.copyWith(id: 'demo', updatedAt: DateTime.now().toUtc());

  @override
  Future<Formation> publish(Formation f) async {
    final now = DateTime.now().toUtc();
    return _current = f.copyWith(id: 'demo', publishedAt: now, updatedAt: now);
  }
}
