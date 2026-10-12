import '../../core/auth/profile.dart';
import '../../core/italian_time.dart';
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

  /// Gol segnati (dai marcatori delle partite giocate dalle sue squadre).
  final int goals;

  /// Mesi nel club.
  final int months;

  /// % di vittorie delle sue squadre; null se non ci sono partite giocate.
  final int? winRate;

  /// [roster]: tutta la rosa, per riconoscere i marcatori come fa il server
  /// (omonimi compresi).
  static CardStats of(
    Member m, {
    required List<AttendanceEntry> attendance,
    required List<ClubMatch> matches,
    required List<Member> roster,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    // Le risposte date in anticipo per i giorni che devono ancora venire non
    // contano: solo fino a oggi in ora italiana, come sul server.
    final mine = historyOf(m.id, attendance, italianDay(today));
    final stats = AttendanceStats(mine);
    final came = stats.present + stats.late;
    final months =
        (today.year - m.joinedAt.year) * 12 + today.month - m.joinedAt.month;
    final played = matches
        .where(
          (x) =>
              m.teams.contains(x.team) && x.outcome != MatchOutcome.daGiocare,
        )
        .toList();
    final record = MatchRecord(played);
    return CardStats(
      presence: stats.percent,
      punctuality: came == 0 ? null : (stats.present / came * 100).round(),
      nights: came,
      goals: goalsOf(m, played, roster),
      months: months < 0 ? 0 : months,
      winRate: record.played == 0
          ? null
          : (record.wins / record.played * 100).round(),
    );
  }
}

/// Gol di [m] nelle partite giocate dalle sue squadre: in ogni partita i marcatori si
/// cercano solo tra i giocatori della squadra che l'ha giocata (attivi, non in attesa),
/// come fa il server.
int goalsOf(Member m, Iterable<ClubMatch> matches, Iterable<Member> roster) {
  var total = 0;
  for (final x in matches) {
    if (!m.teams.contains(x.team) || x.outcome == MatchOutcome.daGiocare) {
      continue;
    }
    final players = [
      for (final p in roster)
        if (p.active && p.role != ClubRole.pending && p.teams.contains(x.team))
          p,
    ];
    total += scorerGoals(x.scorers, players)[m.id] ?? 0;
  }
  return total;
}

final _scorerItem = RegExp(
  r'^(.*?)(?:\s*[x×(]\s*(\d+)\s*\)?|\s+(\d+))?\s*$',
  caseSensitive: false,
);

/// Gol per giocatore (id → gol) in un elenco marcatori scritto a mano, es.
/// "Rossi 2, Neri" o "Rossi (2), Diavolo_9 x2", come la funzione `scorer_goals` del
/// database: ogni nome vale per un solo giocatore tra [players], cercato prima per nome
/// sulla carta, poi per cognome, poi per gamertag; se allo stesso livello corrispondono
/// due giocatori (omonimi), quel nome non assegna gol a nessuno.
Map<String, int> scorerGoals(String? scorers, Iterable<Member> players) {
  final goals = <String, int>{};
  if (scorers == null || scorers.trim().isEmpty) return goals;
  final levels = <String? Function(Member)>[
    (p) => _norm(p.displayName),
    (p) => _norm(p.displayName).split(' ').last,
    (p) => p.gamertag?.trim().toLowerCase(),
  ];
  for (final raw in scorers.split(RegExp(r'[,;\n]'))) {
    final match = _scorerItem.firstMatch(raw.trim());
    if (match == null) continue;
    final name = _norm(match.group(1) ?? '');
    if (name.isEmpty) continue;
    final count = int.tryParse(match.group(2) ?? match.group(3) ?? '') ?? 1;
    for (final key in levels) {
      final found = {
        for (final p in players)
          if (key(p) == name) p.id,
      };
      if (found.isEmpty) continue;
      if (found.length == 1) {
        goals.update(found.single, (g) => g + count, ifAbsent: () => count);
      }
      break;
    }
  }
  return goals;
}

/// Gol di [m] in un elenco marcatori, cercando tra [players] (di solito la squadra;
/// senza, solo [m]).
int goalsIn(String? scorers, Member m, [Iterable<Member>? players]) =>
    scorerGoals(scorers, players ?? [m])[m.id] ?? 0;

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
    teams.length == 2 ? 'MILAN AC · FUTURO' : teams.first.label;
