import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/teams.dart';

/// Media dei voti ricevuti da un giocatore in una partita.
class RatingSummary {
  const RatingSummary({
    required this.playerId,
    required this.average,
    required this.votes,
    this.isMvp = false,
  });
  final String playerId;
  final double average;
  final int votes;

  /// Uomo partita: la media più alta con almeno 2 voti.
  final bool isMvp;
}

/// Uomo partita di una partita votata.
class MvpAward {
  const MvpAward({
    required this.matchId,
    required this.playerId,
    required this.average,
    required this.votes,
    required this.playedAt,
    required this.team,
  });
  final String matchId;
  final String playerId;
  final double average;
  final int votes;
  final DateTime playedAt;
  final Team team;
}

/// Giocatore nella Squadra della settimana.
class TotwEntry {
  const TotwEntry({
    required this.playerId,
    required this.average,
    required this.votes,
    required this.matches,
  });
  final String playerId;
  final double average;
  final int votes;
  final int matches;
}

/// Numeri di sempre per i traguardi.
class PlayerStats {
  const PlayerStats({
    this.presences = 0,
    this.late = 0,
    this.cleanMonth = false,
    this.mvp = 0,
    this.totw = 0,
  });
  final int presences;
  final int late;

  /// Almeno un mese con 8 serate e nessun ritardo.
  final bool cleanMonth;
  final int mvp;
  final int totw;

  factory PlayerStats.fromMap(Map<String, dynamic> m) => PlayerStats(
    presences: (m['presences'] as num?)?.toInt() ?? 0,
    late: (m['late'] as num?)?.toInt() ?? 0,
    cleanMonth: (m['clean_month'] as bool?) ?? false,
    mvp: (m['mvp'] as num?)?.toInt() ?? 0,
    totw: (m['totw'] as num?)?.toInt() ?? 0,
  );
}

/// Lunedì della settimana di [d].
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

abstract class RatingsRepository {
  /// I miei voti per la partita (giocatore → voto).
  Future<Map<String, int>> myRatings(String matchId);

  /// Salva i miei voti: chi non è nella mappa non viene votato.
  Future<void> saveRatings(String matchId, Map<String, int> ratings);
  Future<List<RatingSummary>> summary(String matchId);
  Future<List<MvpAward>> mvps();
  Future<List<TotwEntry>> teamOfTheWeek(DateTime week, Team team);
  Future<PlayerStats> playerStats(String playerId);
}

final ratingsRepositoryProvider = Provider<RatingsRepository>((ref) {
  if (AppConfig.isDemo) return DemoRatingsRepository();
  return _SupabaseRatingsRepository(ref);
});

final myRatingsProvider = FutureProvider.family<Map<String, int>, String>(
  (ref, matchId) => ref.watch(ratingsRepositoryProvider).myRatings(matchId),
);

final ratingSummaryProvider =
    FutureProvider.family<List<RatingSummary>, String>(
      (ref, matchId) => ref.watch(ratingsRepositoryProvider).summary(matchId),
    );

final mvpsProvider = FutureProvider<List<MvpAward>>(
  (ref) => ref.watch(ratingsRepositoryProvider).mvps(),
);

final totwProvider = FutureProvider.family<List<TotwEntry>, (DateTime, Team)>(
  (ref, key) =>
      ref.watch(ratingsRepositoryProvider).teamOfTheWeek(key.$1, key.$2),
);

final playerStatsProvider = FutureProvider.family<PlayerStats, String>(
  (ref, id) => ref.watch(ratingsRepositoryProvider).playerStats(id),
);

/// Uomo partita negli ultimi 7 giorni (per la carta speciale), se c'è.
final recentMvpProvider = Provider.family<MvpAward?, String>((ref, playerId) {
  final since = DateTime.now().subtract(const Duration(days: 7));
  final list =
      (ref.watch(mvpsProvider).value ?? const <MvpAward>[])
          .where((a) => a.playerId == playerId && a.playedAt.isAfter(since))
          .toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  return list.firstOrNull;
});

/// Dopo un voto: ricarica medie, Uomo partita, Squadra della settimana e traguardi.
void refreshRatings(WidgetRef ref, String matchId) {
  ref
    ..invalidate(myRatingsProvider(matchId))
    ..invalidate(ratingSummaryProvider(matchId))
    ..invalidate(mvpsProvider)
    ..invalidate(totwProvider)
    ..invalidate(playerStatsProvider);
}

class _SupabaseRatingsRepository implements RatingsRepository {
  _SupabaseRatingsRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

  @override
  Future<Map<String, int>> myRatings(String matchId) async {
    final rows = await _client
        .from('match_ratings')
        .select('player_id, rating')
        .eq('match_id', matchId)
        .eq('voter_id', _client.auth.currentUser!.id);
    return {
      for (final r in rows)
        r['player_id'] as String: (r['rating'] as num).toInt(),
    };
  }

  @override
  Future<void> saveRatings(String matchId, Map<String, int> ratings) async {
    final me = _client.auth.currentUser!.id;
    await _client
        .from('match_ratings')
        .delete()
        .eq('match_id', matchId)
        .eq('voter_id', me);
    if (ratings.isEmpty) return;
    await _client.from('match_ratings').insert([
      for (final e in ratings.entries)
        {
          'match_id': matchId,
          'voter_id': me,
          'player_id': e.key,
          'rating': e.value,
        },
    ]);
  }

  @override
  Future<List<RatingSummary>> summary(String matchId) async {
    final rows = await _client.rpc(
      'match_rating_summary',
      params: {'p_match': matchId},
    ) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        RatingSummary(
          playerId: r['player_id'] as String,
          average: _num(r['avg_rating']),
          votes: (r['votes'] as num).toInt(),
          isMvp: (r['is_mvp'] as bool?) ?? false,
        ),
    ];
  }

  @override
  Future<List<MvpAward>> mvps() async {
    final rows = await _client.rpc('match_mvps') as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        MvpAward(
          matchId: r['match_id'] as String,
          playerId: r['player_id'] as String,
          average: _num(r['avg_rating']),
          votes: (r['votes'] as num).toInt(),
          playedAt: DateTime.parse(r['played_at'] as String).toLocal(),
          team: Team.parse(r['team']) ?? Team.milanac,
        ),
    ];
  }

  @override
  Future<List<TotwEntry>> teamOfTheWeek(DateTime week, Team team) async {
    final rows = await _client.rpc(
      'team_of_the_week',
      params: {
        'p_week': weekStart(week).toIso8601String().substring(0, 10),
        'p_team': team.name,
      },
    ) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        TotwEntry(
          playerId: r['player_id'] as String,
          average: _num(r['avg_rating']),
          votes: (r['votes'] as num).toInt(),
          matches: (r['matches'] as num).toInt(),
        ),
    ];
  }

  @override
  Future<PlayerStats> playerStats(String playerId) async {
    final data = await _client.rpc(
      'player_stats',
      params: {'p_player': playerId},
    );
    return data is Map<String, dynamic>
        ? PlayerStats.fromMap(data)
        : const PlayerStats();
  }
}

/// Voti in memoria per la demo e i test: stesse regole delle funzioni SQL.
class DemoRatingsRepository implements RatingsRepository {
  DemoRatingsRepository() {
    final now = DateTime.now();
    // Partite della demo (stesse date di DemoMatchesRepository): m1 già votata.
    _played['m1'] = (now.subtract(const Duration(days: 5)), Team.milanac);
    _played['m2'] = (now.subtract(const Duration(days: 9)), Team.futuro);
    _played['m3'] = (now.subtract(const Duration(days: 12)), Team.milanac);
    _votes.addAll([
      ('m1', 'p3', 'p2', 9),
      ('m1', 'p4', 'p2', 8),
      ('m1', 'p2', 'p3', 7),
      ('m1', 'p4', 'p3', 6),
      ('m1', 'p2', 'p4', 6),
      ('m1', 'p3', 'p4', 7),
    ]);
  }

  /// partita → (data, squadra)
  final _played = <String, (DateTime, Team)>{};

  /// (partita, votante, votato, voto)
  final _votes = <(String, String, String, int)>[];
  static const _me = 'demo';

  @override
  Future<Map<String, int>> myRatings(String matchId) async => {
    for (final v in _votes)
      if (v.$1 == matchId && v.$2 == _me) v.$3: v.$4,
  };

  @override
  Future<void> saveRatings(String matchId, Map<String, int> ratings) async {
    _votes.removeWhere((v) => v.$1 == matchId && v.$2 == _me);
    for (final e in ratings.entries) {
      _votes.add((matchId, _me, e.key, e.value));
    }
  }

  List<RatingSummary> _summary(Iterable<(String, String, String, int)> votes) {
    final byPlayer = <String, List<int>>{};
    for (final v in votes) {
      byPlayer.putIfAbsent(v.$3, () => []).add(v.$4);
    }
    final list =
        [
          for (final e in byPlayer.entries)
            RatingSummary(
              playerId: e.key,
              average:
                  (e.value.reduce((a, b) => a + b) / e.value.length * 10)
                      .round() /
                  10,
              votes: e.value.length,
            ),
        ]..sort((a, b) {
          final enough = (b.votes >= 2 ? 1 : 0) - (a.votes >= 2 ? 1 : 0);
          if (enough != 0) return enough;
          final avg = b.average.compareTo(a.average);
          return avg != 0 ? avg : b.votes - a.votes;
        });
    return [
      for (final (i, s) in list.indexed)
        RatingSummary(
          playerId: s.playerId,
          average: s.average,
          votes: s.votes,
          isMvp: i == 0 && s.votes >= 2,
        ),
    ];
  }

  @override
  Future<List<RatingSummary>> summary(String matchId) async =>
      _summary(_votes.where((v) => v.$1 == matchId));

  @override
  Future<List<MvpAward>> mvps() async => [
    for (final matchId in {for (final v in _votes) v.$1})
      if (_summary(_votes.where((v) => v.$1 == matchId)).firstOrNull
          case final top? when top.isMvp)
        MvpAward(
          matchId: matchId,
          playerId: top.playerId,
          average: top.average,
          votes: top.votes,
          playedAt: _played[matchId]?.$1 ?? DateTime.now(),
          team: _played[matchId]?.$2 ?? Team.milanac,
        ),
  ];

  @override
  Future<List<TotwEntry>> teamOfTheWeek(DateTime week, Team team) async {
    final start = weekStart(week);
    final end = start.add(const Duration(days: 7));
    final inWeek = _votes.where((v) {
      final p = _played[v.$1];
      return p != null &&
          p.$2 == team &&
          !p.$1.isBefore(start) &&
          p.$1.isBefore(end);
    });
    return [
      for (final s in _summary(inWeek).where((s) => s.votes >= 2).take(11))
        TotwEntry(
          playerId: s.playerId,
          average: s.average,
          votes: s.votes,
          matches: {
            for (final v in inWeek)
              if (v.$3 == s.playerId) v.$1,
          }.length,
        ),
    ];
  }

  @override
  Future<PlayerStats> playerStats(String playerId) async {
    final awards = await mvps();
    return PlayerStats(
      presences: playerId == 'p2' ? 48 : 12,
      late: playerId == 'p3' ? 3 : 0,
      cleanMonth: playerId != 'p3',
      mvp: awards.where((a) => a.playerId == playerId).length,
      totw: (await teamOfTheWeek(
        DateTime.now(),
        Team.milanac,
      )).where((t) => t.playerId == playerId).length,
    );
  }
}
