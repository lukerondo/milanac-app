import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/teams.dart';

enum TournamentStatus {
  iscrizioni('Iscrizioni aperte'),
  inCorso('In corso'),
  concluso('Concluso');

  const TournamentStatus(this.label);
  final String label;

  /// Nome nel database (in_corso).
  String get db => this == inCorso ? 'in_corso' : name;

  static TournamentStatus parse(Object? v) =>
      values.firstWhere((s) => s.db == v, orElse: () => inCorso);
}

/// Torneo a cui partecipa una squadra del club (tabella `tournaments`).
class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    this.organizer,
    this.url,
    this.team = Team.milanac,
    this.status = TournamentStatus.inCorso,
    this.startsOn,
    this.endsOn,
    this.notes,
  });

  final String id;
  final String name;
  final String? organizer;
  final String? url;
  final Team team;
  final TournamentStatus status;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String? notes;

  factory Tournament.fromMap(Map<String, dynamic> m) {
    DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
    return Tournament(
      id: m['id'] as String,
      name: m['name'] as String,
      organizer: m['organizer'] as String?,
      url: m['url'] as String?,
      team: Team.parse(m['team']) ?? Team.milanac,
      status: TournamentStatus.parse(m['status']),
      startsOn: date(m['starts_on']),
      endsOn: date(m['ends_on']),
      notes: m['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    String? day(DateTime? d) => d?.toIso8601String().substring(0, 10);
    return {
      'name': name,
      'organizer': organizer,
      'url': url,
      'team': team.name,
      'status': status.db,
      'starts_on': day(startsOn),
      'ends_on': day(endsOn),
      'notes': notes,
    };
  }
}

/// Riga della classifica: punti e partite giocate si calcolano da V/N/P.
class StandingRow {
  const StandingRow({
    required this.teamName,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.isUs = false,
  });

  final String teamName;
  final int won, drawn, lost, goalsFor, goalsAgainst;

  /// La riga della nostra squadra (evidenziata).
  final bool isUs;

  int get played => won + drawn + lost;
  int get points => won * 3 + drawn;
  int get goalDiff => goalsFor - goalsAgainst;

  factory StandingRow.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return StandingRow(
      teamName: m['team_name'] as String,
      won: n('won'),
      drawn: n('drawn'),
      lost: n('lost'),
      goalsFor: n('goals_for'),
      goalsAgainst: n('goals_against'),
      isUs: (m['is_us'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap(String tournamentId) => {
    'tournament_id': tournamentId,
    'team_name': teamName,
    'won': won,
    'drawn': drawn,
    'lost': lost,
    'goals_for': goalsFor,
    'goals_against': goalsAgainst,
    'is_us': isUs,
  };
}

/// Classifica ordinata: punti, differenza reti, gol fatti, nome.
List<StandingRow> sortStandings(Iterable<StandingRow> rows) =>
    rows.toList()..sort((a, b) {
      for (final c in [
        b.points - a.points,
        b.goalDiff - a.goalDiff,
        b.goalsFor - a.goalsFor,
      ]) {
        if (c != 0) return c;
      }
      return a.teamName.compareTo(b.teamName);
    });

abstract class TournamentsRepository {
  Stream<List<Tournament>> watchAll();

  /// Crea (id vuoto) o aggiorna; restituisce l'id.
  Future<String> save(Tournament t);
  Future<void> delete(String id);
  Future<List<StandingRow>> standings(String tournamentId);

  /// Sostituisce l'intera classifica del torneo.
  Future<void> saveStandings(String tournamentId, List<StandingRow> rows);
}

final tournamentsRepositoryProvider = Provider<TournamentsRepository>((ref) {
  if (AppConfig.isDemo) return DemoTournamentsRepository();
  return _SupabaseTournamentsRepository(ref);
});

final tournamentsProvider = StreamProvider<List<Tournament>>(
  (ref) => ref.watch(tournamentsRepositoryProvider).watchAll(),
);

final standingsProvider = FutureProvider.family<List<StandingRow>, String>(
  (ref, id) async => sortStandings(
    await ref.watch(tournamentsRepositoryProvider).standings(id),
  ),
);

class _SupabaseTournamentsRepository implements TournamentsRepository {
  _SupabaseTournamentsRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Stream<List<Tournament>> watchAll() => _client
      .from('tournaments')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Tournament.fromMap).toList());

  @override
  Future<String> save(Tournament t) async {
    if (t.id.isEmpty) {
      final row = await _client
          .from('tournaments')
          .insert(t.toMap())
          .select('id')
          .single();
      return row['id'] as String;
    }
    await _client.from('tournaments').update(t.toMap()).eq('id', t.id);
    return t.id;
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('tournaments').delete().eq('id', id);
  }

  @override
  Future<List<StandingRow>> standings(String tournamentId) async {
    final rows = await _client
        .from('tournament_standings')
        .select()
        .eq('tournament_id', tournamentId);
    return rows.map(StandingRow.fromMap).toList();
  }

  @override
  Future<void> saveStandings(
    String tournamentId,
    List<StandingRow> rows,
  ) async {
    await _client
        .from('tournament_standings')
        .delete()
        .eq('tournament_id', tournamentId);
    if (rows.isEmpty) return;
    await _client.from('tournament_standings').insert([
      for (final r in rows) r.toMap(tournamentId),
    ]);
  }
}

class DemoTournamentsRepository implements TournamentsRepository {
  final _tournaments = <Tournament>[
    Tournament(
      id: 'tr1',
      name: 'FVPA Serie B',
      organizer: 'FVPA',
      url: 'https://www.fvpa.it/',
      startsOn: DateTime(2026, 9, 15),
    ),
    const Tournament(
      id: 'tr2',
      name: 'Coppa Riserve',
      organizer: 'Torneo amatoriale',
      team: Team.futuro,
      status: TournamentStatus.iscrizioni,
    ),
  ];
  final _standings = <String, List<StandingRow>>{
    'tr1': const [
      StandingRow(
        teamName: 'Dinamo Pixel',
        won: 2,
        lost: 1,
        goalsFor: 6,
        goalsAgainst: 4,
      ),
      StandingRow(
        teamName: 'MILANAC',
        won: 2,
        drawn: 1,
        goalsFor: 7,
        goalsAgainst: 3,
        isUs: true,
      ),
      StandingRow(
        teamName: 'Sporting Joypad',
        won: 1,
        drawn: 1,
        lost: 1,
        goalsFor: 4,
        goalsAgainst: 4,
      ),
    ],
  };
  final _changes = StreamController<void>.broadcast();
  var _next = 10;

  @override
  Stream<List<Tournament>> watchAll() async* {
    yield List.of(_tournaments);
    yield* _changes.stream.map((_) => List.of(_tournaments));
  }

  @override
  Future<String> save(Tournament t) async {
    final id = t.id.isEmpty ? 'tr${_next++}' : t.id;
    final saved = Tournament(
      id: id,
      name: t.name,
      organizer: t.organizer,
      url: t.url,
      team: t.team,
      status: t.status,
      startsOn: t.startsOn,
      endsOn: t.endsOn,
      notes: t.notes,
    );
    final i = _tournaments.indexWhere((x) => x.id == id);
    i >= 0 ? _tournaments[i] = saved : _tournaments.insert(0, saved);
    _changes.add(null);
    return id;
  }

  @override
  Future<void> delete(String id) async {
    _tournaments.removeWhere((t) => t.id == id);
    _standings.remove(id);
    _changes.add(null);
  }

  @override
  Future<List<StandingRow>> standings(String id) async =>
      List.of(_standings[id] ?? const []);

  @override
  Future<void> saveStandings(String id, List<StandingRow> rows) async =>
      _standings[id] = List.of(rows);
}
