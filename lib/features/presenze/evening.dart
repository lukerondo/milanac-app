import '../../core/config.dart';
import '../../core/teams.dart';
import '../calendario/club_event.dart';
import '../rosa/member.dart';

/// Le serate del club (regolamento): allenamenti, campionato, tornei e amichevoli si
/// giocano dal lunedì al venerdì, dalle 21:30 alle 23:30 italiane.
const eveningHours =
    '${AppConfig.defaultArrivalTime}–${AppConfig.eveningEndTime}';

/// Dal lunedì al venerdì c'è sempre la serata (l'allenamento, se non c'è altro); sabato e
/// domenica solo se il Direttivo mette un evento in calendario. Come `club_evening` sul
/// server.
bool isClubWeekday(DateTime day) => day.weekday <= DateTime.friday;

/// L'allenamento di una sera dal lunedì al venerdì (21:30 italiane), quando il Direttivo non
/// ha messo in calendario altro per quel giorno.
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
/// altrimenti, dal lunedì al venerdì, l'allenamento delle 21:30. Sabato e domenica senza
/// eventi non c'è serata (null): niente risposte, promemoria né assenze. Le riunioni non
/// chiedono presenze.
ClubEvent? eveningEvent(
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
  if (!isClubWeekday(day)) return null;
  return trainingOn(day, team: teams.length == 1 ? teams.first : null);
}

/// La prima serata dopo [day] per chi gioca in [teams] (al più tardi il lunedì dopo).
({DateTime day, ClubEvent event}) nextEvening(
  List<ClubEvent> events,
  DateTime day, {
  Set<Team> teams = const {Team.milanac, Team.futuro},
}) {
  for (var i = 1; ; i++) {
    final next = DateTime(day.year, day.month, day.day + i);
    final event = eveningEvent(events, next, teams: teams);
    if (event != null) return (day: next, event: event);
  }
}

/// I membri che hanno la serata di [day]: tutti dal lunedì al venerdì; sabato e domenica
/// solo chi gioca nella squadra di un evento (come le assenze automatiche sul server).
List<Member> playingTonight(
  Iterable<Member> members,
  List<ClubEvent> events,
  DateTime day,
) => [
  for (final m in members)
    if (eveningEvent(events, day, teams: m.teams) != null) m,
];

/// Squadra "principale" di un membro: MILANAC se ci gioca (anche con il Futuro).
Team mainTeam(Set<Team> teams) =>
    teams.contains(Team.milanac) ? Team.milanac : Team.futuro;

/// Nome della squadra nei selettori e nei filtri ("MILANAC", "FUTURO"): il nome breve,
/// maiuscolo come MILANAC accanto.
String teamTabLabel(Team t) => t.short;

/// Titolo e dettaglio di una partita dal titolo dell'evento: "FVPA – 3ª giornata vs
/// Atletico Virtuale" diventa "MILANAC – Atletico Virtuale" con "FVPA – 3ª giornata".
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
