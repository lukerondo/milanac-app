import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../formazione/modules.dart';
import '../presenze/attendance.dart';
import '../presenze/attendance_repository.dart';
import '../presenze/presenze_page.dart';
import '../rosa/member.dart';
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

/// Dati della serata per il pannello e per il bottone in Home.
class _Tonight {
  _Tonight(WidgetRef ref) {
    me = ref.watch(profileProvider).value;
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final entries =
        ref.watch(attendanceProvider).value ?? const <AttendanceEntry>[];
    members = (ref.watch(rosaProvider).value ?? const [])
        .where((m) => m.active && m.role != ClubRole.pending)
        .toList();
    final myTeams = me?.teams ?? const {Team.milanac};
    formations = [
      for (final t in Team.values)
        if (myTeams.contains(t)) ref.watch(formationProvider(t)).value,
    ].nonNulls.toList();
    final now = DateTime.now();
    event = tonightEvent(events, now, teams: myTeams);
    day = dayOnly(now);
    tonight = {
      for (final e in entries.where((e) => e.date == day)) e.playerId: e,
    };
  }

  late final Profile? me;
  late final List<Member> members;
  late final List<Formation> formations;
  late final ClubEvent event;
  late final DateTime day;
  late final Map<String, AttendanceEntry> tonight;

  AttendanceEntry? get mine => me == null ? null : tonight[me!.id];
  bool get isMember => me != null && members.any((m) => m.id == me!.id);
  bool get needsReply => isMember && mine == null;
  int count(AttendanceStatus s) =>
      tonight.values.where((e) => e.status == s).length;
  int get missing => members.where((m) => !tonight.containsKey(m.id)).length;
}

/// Bottone tondo in basso a destra della Home (come quello di una chat):
/// apre il pannello della serata. Il pallino dorato ricorda di rispondere.
class TonightFab extends ConsumerWidget {
  const TonightFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = _Tonight(ref);
    return Badge(
      isLabelVisible: t.needsReply,
      smallSize: 14,
      backgroundColor: MilanacColors.gold,
      offset: const Offset(-4, 4),
      child: FloatingActionButton(
        heroTag: 'stasera',
        tooltip: 'Stasera',
        backgroundColor: MilanacColors.red,
        shape: const CircleBorder(),
        onPressed: () {
          HapticFeedback.lightImpact();
          showTonightPanel(context);
        },
        child: const Icon(Icons.stadium_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

/// Pannello rettangolare che entra da destra verso sinistra.
Future<void> showTonightPanel(BuildContext context) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Chiudi',
  barrierColor: Colors.black54,
  transitionDuration: const Duration(milliseconds: 280),
  pageBuilder: (context, _, _) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Material(
            color: MilanacColors.surface,
            elevation: 12,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width < 420 ? width * .9 : 380,
              child: const TonightPanel(),
            ),
          ),
        ),
      ),
    );
  },
  transitionBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

/// Contenuto del pannello: evento, totali (presenti, ritardi, assenti), formazione.
class TonightPanel extends ConsumerWidget {
  const TonightPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = _Tonight(ref);
    final event = t.event;
    final mine = t.mine;

    void go(String path) {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go(path);
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  event.type.color.withValues(alpha: .35),
                  MilanacColors.surface,
                ],
              ),
            ),
            child: Row(
              children: [
                Icon(event.type.icon, color: event.type.color, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STASERA · ${DateFormat('HH:mm').format(event.startsAt)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chiudi',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                _Total(
                  t.count(AttendanceStatus.presente),
                  'Presenti',
                  statusColor(AttendanceStatus.presente),
                ),
                _Total(
                  t.count(AttendanceStatus.ritardo),
                  'Ritardi',
                  statusColor(AttendanceStatus.ritardo),
                ),
                _Total(
                  t.count(AttendanceStatus.assente),
                  'Assenti',
                  statusColor(AttendanceStatus.assente),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              t.missing == 0
                  ? 'Hanno risposto tutti.'
                  : '${t.missing} ${t.missing == 1 ? 'non ha' : 'non hanno'} ancora risposto',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const Divider(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'FORMAZIONE',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 12,
                color: Colors.white60,
              ),
            ),
          ),
          for (final f in t.formations)
            _FormationLine(
              team: t.formations.length > 1 ? f.team : null,
              published: f.isPublishedToday,
              position: t.me == null
                  ? null
                  : f.publishedView.positionOf(t.me!.id),
              onTap: () => go('/formazione'),
            ),
          if (t.isMember) ...[
            const Divider(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                mine == null
                    ? 'Ci sei stasera?'
                    : 'La tua risposta: ${describeAttendance(mine)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
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
                                    playerId: t.me!.id,
                                    date: t.day,
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
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TextButton.icon(
              onPressed: () => go('/presenze'),
              icon: const Icon(Icons.how_to_reg_rounded),
              label: const Text('Apri le presenze'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.value, this.label, this.color);
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _FormationLine extends StatelessWidget {
  const _FormationLine({
    required this.team,
    required this.published,
    required this.position,
    required this.onTap,
  });
  final Team? team;
  final bool published;
  final String? position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final prefix = team == null ? '' : '${team!.short}: ';
    final text =
        prefix +
        (!published
            ? 'non ancora pubblicata'
            : position != null
            ? 'pubblicata · giochi $position titolare'
            : 'pubblicata · parti dalla panchina');
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        published ? Icons.verified_rounded : Icons.hourglass_empty_rounded,
        color: published ? const Color(0xFF2E9E5B) : Colors.white38,
      ),
      title: Text(
        text,
        style: TextStyle(color: published ? Colors.white : Colors.white54),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    );
  }
}
