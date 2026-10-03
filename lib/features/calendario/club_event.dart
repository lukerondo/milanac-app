import 'package:flutter/material.dart';

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
    startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
    description: m['description'] as String?,
    location: m['location'] as String?,
    team: Team.parse(m['team']),
  );

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'title': title,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'description': description,
    'location': location,
    'team': team?.name,
  };
}
