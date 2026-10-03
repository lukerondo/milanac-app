import '../../core/teams.dart';
import '../presenze/attendance.dart';
import '../risultati/match.dart';
import '../rosa/member.dart';

/// Le sei statistiche della carta, calcolate dai dati del club.
class CardStats {
  const CardStats({
    required this.presence,
    required this.punctuality,
    required this.nights,
    required this.goals,
    required this.months,
    required this.winRate,
  });

  /// % di serate presenti (anche in ritardo) negli ultimi 60 giorni.
  final int presence;

  /// % di presenze puntuali (non in ritardo); null se non ha mai risposto "ci sono".
  final int? punctuality;

  /// Serate in cui c'era, ultimi 60 giorni.
  final int nights;

  /// Gol segnati (dai marcatori delle partite).
  final int goals;

  /// Mesi nel club.
  final int months;

  /// % di vittorie delle sue squadre; null se non ci sono partite giocate.
  final int? winRate;

  static CardStats of(
    Member m, {
    required List<AttendanceEntry> attendance,
    required List<ClubMatch> matches,
    DateTime? now,
  }) {
    final mine = attendance.where((e) => e.playerId == m.id).toList();
    final stats = AttendanceStats(mine);
    final came = stats.present + stats.late;
    final today = now ?? DateTime.now();
    final months =
        (today.year - m.joinedAt.year) * 12 + today.month - m.joinedAt.month;
    final played = matches.where(
      (x) => m.teams.contains(x.team) && x.outcome != MatchOutcome.daGiocare,
    );
    final record = MatchRecord(played);
    return CardStats(
      presence: stats.percent,
      punctuality: came == 0 ? null : (stats.present / came * 100).round(),
      nights: came,
      goals: matches.fold(0, (sum, x) => sum + goalsIn(x.scorers, m)),
      months: months < 0 ? 0 : months,
      winRate: record.played == 0
          ? null
          : (record.wins / record.played * 100).round(),
    );
  }
}

/// Gol di [m] in un elenco marcatori scritto a mano, es. "Rossi 2, Neri" o
/// "Rossi (2), Diavolo_9 x2". Riconosce cognome, nome completo o gamertag.
int goalsIn(String? scorers, Member m) {
  if (scorers == null || scorers.trim().isEmpty) return 0;
  final names = {
    _norm(m.displayName),
    _norm(m.displayName.split(' ').last),
    if (m.gamertag != null && m.gamertag!.isNotEmpty) _norm(m.gamertag!),
  }..remove('');
  var total = 0;
  for (final raw in scorers.split(RegExp(r'[,;\n]'))) {
    final match = RegExp(
      r'^(.*?)(?:\s*[x×(]\s*(\d+)\s*\)?|\s+(\d+))?\s*$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) continue;
    final name = _norm(match.group(1) ?? '');
    final count = int.tryParse(match.group(2) ?? match.group(3) ?? '') ?? 1;
    if (names.contains(name)) total += count;
  }
  return total;
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Livello della carta in base all'overall, come le carte di FUT.
enum CardTier { vuota, bronzo, argento, oro, rossonera }

CardTier tierOf(int? overall) => switch (overall) {
  null => CardTier.vuota,
  < 65 => CardTier.bronzo,
  < 75 => CardTier.argento,
  < 85 => CardTier.oro,
  _ => CardTier.rossonera,
};

/// Etichette brevi delle squadre per la carta.
String teamsLabel(Set<Team> teams) =>
    teams.length == 2 ? 'MILANAC · FUTURO' : teams.first.label;
