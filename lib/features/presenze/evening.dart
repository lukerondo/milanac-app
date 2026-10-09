import '../../core/config.dart';
import '../../core/teams.dart';
import '../calendario/club_event.dart';

/// L'allenamento di ogni sera (lunedì-domenica, 21:30), quando il Direttivo non ha
/// messo in calendario altro per quel giorno.
ClubEvent trainingOn(DateTime day, {Team? team}) {
  final parts = AppConfig.defaultArrivalTime.split(':');
  return ClubEvent(
    id: '',
    type: EventType.allenamento,
    title: 'Allenamento',
    team: team,
    startsAt: DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    ),
  );
}

/// L'appuntamento della serata di [day] per chi gioca in [teams]: il primo evento
/// del giorno che li riguarda (partita, amichevole o allenamento a un altro orario),
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
