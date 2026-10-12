import 'package:flutter/material.dart';

import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';

enum EventType {
  torneo('Partita torneo', Icons.emoji_events_rounded, MilanacColors.red),
  amichevole('Amichevole', Icons.handshake_rounded, Color(0xFF3B82F6)),
  allenamento('Allenamento', Icons.fitness_center_rounded, Color(0xFF2E9E5B)),
  riunione('Riunione', Icons.groups_rounded, MilanacColors.gold),
  altro('Altro', Icons.event_rounded, Colors.white54);

  const EventType(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  bool get isMatch => this == torneo || this == amichevole;
}

/// Evento del calendario (tabella `events`).
class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.startsAt,
    this.description,
    this.location,
    this.team,
  });

  final String id;
  final EventType type;
  final String title;

  /// Inizio in ora italiana: anno, mese, giorno, ore e minuti come in Italia (vedi
  /// [italianClock]), così tutti vedono gli stessi orari e gli stessi giorni, anche
  /// con il telefono su un altro fuso. Si confronta solo con altre ore italiane.
  final DateTime startsAt;
  final String? description;
  final String? location;

  /// Squadra interessata (null = tutto il club).
  final Team? team;

  /// L'evento riguarda chi gioca in [teams]?
  bool concerns(Set<Team> teams) => team == null || teams.contains(team);

  factory ClubEvent.fromMap(Map<String, dynamic> m) => ClubEvent(
    id: m['id'] as String,
    type: EventType.values.byName(m['type'] as String),
    title: m['title'] as String,
    startsAt: italianClock(DateTime.parse(m['starts_at'] as String)),
    description: m['description'] as String?,
    location: m['location'] as String?,
    team: Team.parse(m['team']),
  );

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'title': title,
    'starts_at': fromItalianClock(startsAt).toIso8601String(),
    'description': description,
    'location': location,
    'team': team?.name,
  };
}

/// Primo giorno del calendario del club (eventi e presenze).
final calendarFirstDay = DateTime(2024);

/// Ultimo giorno del calendario: la fine dell'anno tra tre anni. Lo stesso limite vale per
/// l'editor degli eventi e per le pagine, così ogni evento si apre (anche da una notifica).
DateTime calendarLastDay(DateTime today) => DateTime(today.year + 3, 12, 31);

/// [day] (solo il giorno) riportato dentro i limiti del calendario.
DateTime clampToCalendar(DateTime day, DateTime today) {
  final d = DateTime(day.year, day.month, day.day);
  final last = calendarLastDay(today);
  if (d.isBefore(calendarFirstDay)) return calendarFirstDay;
  if (d.isAfter(last)) return last;
  return d;
}
