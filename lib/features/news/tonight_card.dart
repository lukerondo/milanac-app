import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../formazione/formation_repository.dart';
import '../presenze/attendance.dart';
import '../presenze/attendance_repository.dart';
import '../presenze/presenze_page.dart';
import '../rosa/rosa_repository.dart';

/// Evento della serata: il primo in calendario oggi (tra quelli delle [teams]
/// del giocatore), altrimenti l'allenamento delle 21:30.
ClubEvent tonightEvent(
  List<ClubEvent> events,
  DateTime now, {
  Set<Team> teams = const {Team.milanac, Team.futuro},
}) {
  final today =
      events
          .where(
            (e) =>
                e.startsAt.year == now.year &&
                e.startsAt.month == now.month &&
                e.startsAt.day == now.day &&
                e.type != EventType.riunione &&
                e.concerns(teams),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (today.isNotEmpty) return today.first;
  final parts = AppConfig.defaultArrivalTime.split(':');
  return ClubEvent(
    id: '',
    type: EventType.allenamento,
    title: 'Allenamento',
    startsAt: DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    ),
  );
}

/// Riquadro "STASERA" in cima alla Home: evento, la tua presenza, chi c'è, formazione.
class TonightCard extends ConsumerWidget {
  const TonightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final entries =
        ref.watch(attendanceProvider).value ?? const <AttendanceEntry>[];
    final members = (ref.watch(rosaProvider).value ?? const [])
        .where((m) => m.active && m.role != ClubRole.pending)
        .toList();
    final myTeams = me?.teams ?? const {Team.milanac};
    final formations = [
      for (final t in Team.values)
        if (myTeams.contains(t)) ref.watch(formationProvider(t)).value,
    ].nonNulls.toList();

    final now = DateTime.now();
    final event = tonightEvent(events, now, teams: myTeams);
    final day = dayOnly(now);
    final tonight = {
      for (final e in entries.where((e) => e.date == day)) e.playerId: e,
    };
    final mine = me == null ? null : tonight[me.id];
    int count(AttendanceStatus s) =>
        tonight.values.where((e) => e.status == s).length;
    final missing = members.where((m) => !tonight.containsKey(m.id)).length;
    final isMember = me != null && members.any((m) => m.id == me.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              event.type.color.withValues(alpha: .28),
              MilanacColors.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(event.type.icon, color: event.type.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STASERA · ${DateFormat('HH:mm').format(event.startsAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  event.type.label.toUpperCase(),
                  style: TextStyle(
                    color: event.type.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              event.title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (isMember) ...[
              const SizedBox(height: 12),
              Text(
                mine == null
                    ? 'Ci sei stasera?'
                    : 'La tua risposta: ${describeAttendance(mine)}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final s in AttendanceStatus.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: AttendanceStatusButton(
                          status: s,
                          selected: mine?.status == s,
                          onPressed: () async {
                            final input = await editAttendance(
                              context,
                              status: s,
                              initialTime: mine?.arrivalTime,
                              initialNote: mine?.note,
                            );
                            if (input == null) return;
                            await ref
                                .read(attendanceRepositoryProvider)
                                .save(
                                  AttendanceEntry(
                                    playerId: me.id,
                                    date: day,
                                    status: s,
                                    arrivalTime: input.time,
                                    note: input.note,
                                  ),
                                );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: () => context.go('/presenze'),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _Count(
                      count(AttendanceStatus.presente),
                      'presenti',
                      statusColor(AttendanceStatus.presente),
                    ),
                    _Count(
                      count(AttendanceStatus.ritardo),
                      'in ritardo',
                      statusColor(AttendanceStatus.ritardo),
                    ),
                    _Count(
                      count(AttendanceStatus.assente),
                      'assenti',
                      statusColor(AttendanceStatus.assente),
                    ),
                    _Count(missing, 'senza risposta', Colors.white54),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            for (final f in formations)
              _FormationLine(
                // Il nome della squadra serve solo a chi gioca in entrambe.
                team: formations.length > 1 ? f.team : null,
                published: f.isPublishedToday,
                position: me == null ? null : f.positionOf(me.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label, this.color);
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$value ',
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
        TextSpan(
          text: label,
          style: const TextStyle(color: Colors.white60),
        ),
      ],
    ),
  );
}

class _FormationLine extends StatelessWidget {
  const _FormationLine({
    required this.team,
    required this.published,
    required this.position,
  });
  final Team? team;
  final bool published;
  final String? position;

  @override
  Widget build(BuildContext context) {
    final prefix = team == null ? '' : '${team!.short}: ';
    final text =
        prefix +
        (!published
            ? 'Formazione non ancora pubblicata'
            : position != null
            ? 'Formazione pubblicata · tu giochi $position titolare'
            : 'Formazione pubblicata · parti dalla panchina');
    return InkWell(
      onTap: () => context.go('/formazione'),
      child: Row(
        children: [
          Icon(
            Icons.sports_soccer_rounded,
            size: 18,
            color: published ? MilanacColors.gold : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: published ? Colors.white : Colors.white54,
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}
