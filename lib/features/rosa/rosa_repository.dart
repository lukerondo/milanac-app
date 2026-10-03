import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import 'member.dart';

abstract class RosaRepository {
  Stream<List<Member>> watchAll();
  Future<void> save(Member member);
  Future<void> remove(String id);
}

final rosaRepositoryProvider = Provider<RosaRepository>((ref) {
  if (AppConfig.isDemo) return DemoRosaRepository();
  return _SupabaseRosaRepository(ref);
});

final rosaProvider = StreamProvider<List<Member>>(
  (ref) => ref.watch(rosaRepositoryProvider).watchAll(),
);

class _SupabaseRosaRepository implements RosaRepository {
  _SupabaseRosaRepository(this._ref);
  final Ref _ref;

  @override
  Stream<List<Member>> watchAll() => _ref
      .read(supabaseProvider)
      .from('profiles')
      .stream(primaryKey: ['id'])
      .order('joined_at', ascending: true)
      .map((rows) => rows.map(Member.fromMap).toList());

  @override
  Future<void> save(Member m) => _ref
      .read(supabaseProvider)
      .from('profiles')
      .update(m.toUpdateMap())
      .eq('id', m.id);

  /// Rifiuta una richiesta di accesso: il profilo viene disattivato (resta in attesa).
  @override
  Future<void> remove(String id) => _ref
      .read(supabaseProvider)
      .from('profiles')
      .update({'active': false})
      .eq('id', id);
}

/// Dati di esempio in memoria per la modalità demo e i test.
class DemoRosaRepository implements RosaRepository {
  DemoRosaRepository() {
    _controller = StreamController<List<Member>>.broadcast(
      onListen: () => _controller.add(List.of(_members)),
    );
  }

  late final StreamController<List<Member>> _controller;

  final _members = <Member>[
    Member(
      id: 'demo',
      displayName: 'Demo Direttivo',
      gamertag: 'MILANAC_Demo',
      role: ClubRole.direttivo,
      fieldPosition: 'CC',
      shirtNumber: 10,
      joinedAt: DateTime(2025, 1, 10),
    ),
    Member(
      id: 'p2',
      displayName: 'Marco Rossi',
      gamertag: 'Diavolo_9',
      role: ClubRole.giocatore,
      fieldPosition: 'ATT',
      shirtNumber: 9,
      joinedAt: DateTime(2025, 2, 3),
    ),
    Member(
      id: 'p3',
      displayName: 'Luca Bianchi',
      gamertag: 'Muro_Rossonero',
      role: ClubRole.giocatore,
      fieldPosition: 'DC',
      shirtNumber: 4,
      joinedAt: DateTime(2025, 3, 15),
    ),
    Member(
      id: 'p4',
      displayName: 'Andrea Neri',
      gamertag: 'Saracinesca1',
      role: ClubRole.giocatore,
      fieldPosition: 'POR',
      shirtNumber: 1,
      joinedAt: DateTime(2025, 4, 20),
    ),
    Member(
      id: 'p5',
      displayName: 'Nuovo Iscritto',
      gamertag: 'Rookie_77',
      role: ClubRole.pending,
      joinedAt: DateTime(2026, 10, 1),
    ),
  ];

  void _emit() => _controller.add(List.of(_members));

  @override
  Stream<List<Member>> watchAll() async* {
    yield List.of(_members);
    yield* _controller.stream;
  }

  @override
  Future<void> save(Member m) async {
    final i = _members.indexWhere((x) => x.id == m.id);
    if (i >= 0) _members[i] = m;
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    _members.removeWhere((m) => m.id == id);
    _emit();
  }
}
