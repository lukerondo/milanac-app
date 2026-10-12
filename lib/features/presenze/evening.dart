import '../../core/config.dart';
import '../../core/teams.dart';
import '../calendario/club_event.dart';

/// L'allenamento di ogni sera (lunedì-domenica, 21:30 italiane), quando il Direttivo non ha
/// messo in calendario altro per quel giorno.
ClubEvent trainingOn(DateTime day, {Team? team}) {
  final parts = AppConfig.defaultArrivalTime.split(':');
  return ClubEvent(
    id: '',
    type: EventType.allenamento,
    title: 'Allenamento',
    team: team,
    // Ora italiana, come tutti gli eventi (vedi ClubEvent.startsAt).
    startsAt: DateTime.utc(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    ),
  );
}

/// L'appuntamento della serata di [day] (giorno italiano) per chi gioca in [teams]: il primo
/// evento del giorno che li riguarda (partita, amichevole o allenamento a un altro orario),
/// altrimenti l'allenamento delle 21:30. Le riunioni non chiedono presenze.
ClubEvent eveningEvent(
  List<ClubEvent> events,
  DateTime day, {
  Set<Team> teams = const {Team.milanac, Team.futuro},
}) {
  final today =
      events
          .where(
            (e) =>
                e.startsAt.year == day.year &&
                e.startsAt.month == day.month &&
                e.startsAt.day == day.day &&
                e.type != EventType.riunione &&
                e.concerns(teams),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (today.isNotEmpty) return today.first;
  return trainingOn(day, team: teams.length == 1 ? teams.first : null);
}

/// Squadra "principale" di un membro: Milan AC se ci gioca (anche con il Futuro).
Team mainTeam(Set<Team> teams) =>
    teams.contains(Team.milanac) ? Team.milanac : Team.futuro;

/// Nome della squadra nei selettori e nei filtri ("Milan AC", "Futuro").
String teamTabLabel(Team t) => t == Team.milanac ? 'Milan AC' : 'Futuro';

/// Titolo e dettaglio di una partita dal titolo dell'evento: "FVPA – 3ª giornata vs
/// Atletico Virtuale" diventa "Milan AC – Atletico Virtuale" con "FVPA – 3ª giornata".
/// Senza "vs" nel titolo resta il titolo com'è.
({String title, String? detail, String? opponent}) matchHeadline(
  ClubEvent e,
  Team team,
) {
  final m = RegExp(
    r'^(.*?)\s+vs\.?\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(e.title.trim());
  if (m == null) return (title: e.title, detail: null, opponent: null);
  final before = m.group(1)!.trim();
  final opponent = m.group(2)!.trim();
  return (
    title: '${team.label} – $opponent',
    detail: before.isEmpty ? null : before,
    opponent: opponent,
  );
}
