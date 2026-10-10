import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/shared_links.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../mondo/mondo_page.dart';
import '../news/news_item.dart';
import '../news/news_page.dart';
import '../news/news_repository.dart';
import '../presenze/attendance.dart';
import '../presenze/attendance_repository.dart';
import '../presenze/evening.dart';
import '../presenze/presenze_page.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

/// La Home: due riquadri, Mondo Proclub e Presenze.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    children: const [MondoPanel(), SizedBox(height: 12), PresenzePanel()],
  );
}

/// Riquadro della Home con titolo, icona e freccia verso la sezione.
class HomePanel extends StatelessWidget {
  const HomePanel({
    super.key,
    required this.title,
    required this.icon,
    required this.onOpen,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onOpen;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: MilanacColors.gold.withValues(alpha: .35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [MilanacColors.redDark, MilanacColors.surface],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: MilanacColors.gold, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: sportFont,
                          fontSize: 18,
                          letterSpacing: 2,
                          color: MilanacColors.gold,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ Mondo Proclub

class MondoPanel extends ConsumerWidget {
  const MondoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final videos = ref.watch(sharedLinksProvider(LinkCategory.video)).value;
    final news = ref.watch(newsProvider).value ?? const <NewsItem>[];
    final now = DateTime.now();

    final latest = (videos ?? const <SharedLink>[])
        .where((l) => l.isPublished)
        .toList()
      ..sort(
        (a, b) => (b.publishedAt ?? b.createdAt ?? DateTime(2000)).compareTo(
          a.publishedAt ?? a.createdAt ?? DateTime(2000),
        ),
      );
    final video = latest.firstOrNull;
    final gameUpdate = news
        .where((n) => n.isGameUpdate && n.isRecent(now))
        .firstOrNull;
    final consoleUpdate = news
        .where(
          (n) =>
              n.isConsoleUpdate &&
              n.isRecent(now) &&
              n.platform != null &&
              n.platform == me?.platform,
        )
        .firstOrNull;

    return HomePanel(
      title: 'Mondo Proclub',
      subtitle: 'Video dei creator, notizie e aggiornamenti',
      icon: Icons.public_rounded,
      onOpen: () => context.go('/mondo'),
      children: [
        if (video != null)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openSharedLink(video.url),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  VideoThumb(url: video.url, width: 96, height: 54),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ULTIMO VIDEO',
                          style: TextStyle(
                            color: MilanacColors.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Nessun video ancora: proponine uno al Direttivo.',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        if (gameUpdate != null) ...[
          const SizedBox(height: 6),
          UpdateBanner(item: gameUpdate, compact: true),
        ],
        if (consoleUpdate != null) ...[
          if (gameUpdate == null) const SizedBox(height: 6),
          UpdateBanner(item: consoleUpdate, compact: true),
        ],
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => context.go('/mondo'),
                icon: const Icon(Icons.smart_display_rounded, size: 18),
                label: const Text('Video'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => context.go('/mondo?scheda=notizie'),
                icon: const Icon(Icons.newspaper_rounded, size: 18),
                label: Text(
                  news.isEmpty ? 'Notizie' : 'Notizie (${news.length})',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Presenze

/// La serata di oggi per la squadra del membro, con la sua risposta e i conteggi.
class PresenzePanel extends ConsumerWidget {
  const PresenzePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final entries =
        ref.watch(attendanceProvider).value ?? const <AttendanceEntry>[];
    final all = ref.watch(rosaProvider).value ?? const <Member>[];
    final now = ref.watch(clockProvider)();
    final today = dayOnly(now);
    final myTeams = me?.teams ?? const {Team.milanac};
    final event = eveningEvent(events, today, teams: myTeams);
    final team = event.team ?? mainTeam(myTeams);
    final members = all
        .where(
          (m) => m.active && m.role != ClubRole.pending && m.teams.contains(team),
        )
        .toList();
    final tonight = {
      for (final e in entries.where((e) => e.date == today)) e.playerId: e,
    };
    final mine = me == null ? null : tonight[me.id];
    final isMember = me != null && members.any((m) => m.id == me.id);
    final open = answersOpen(today, now);
    int count(AttendanceStatus s) =>
        members.where((m) => tonight[m.id]?.status == s).length;
    final missing = members.where((m) => !tonight.containsKey(m.id)).length;

    final status = !isMember
        ? null
        : mine != null
        ? 'La tua risposta: ${describeAttendance(mine)}'
            '${open ? ' · modificabile fino alle $attendanceDeadlineLabel' : ''}'
        : open
        ? 'Ci sei stasera? Rispondi entro le $attendanceDeadlineLabel.'
        : 'Risposte chiuse alle $attendanceDeadlineLabel: chi non ha risposto risulta assente.';

    return HomePanel(
      title: 'Presenze',
      subtitle: 'Stasera · ${team.label}',
      icon: Icons.how_to_reg_rounded,
      onOpen: () => context.go('/presenze'),
      children: [
        Row(
          children: [
            Icon(event.type.icon, color: event.type.color, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event.type.label.toUpperCase()} · ${DateFormat('HH:mm').format(event.startsAt)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (event.title != event.type.label)
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: 8),
          Text(
            status,
            style: TextStyle(
              color: mine == null && open
                  ? MilanacColors.gold
                  : Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
        if (isMember) ...[
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
                      onPressed: open
                          ? () => answerAttendance(
                              context,
                              ref,
                              playerId: me.id,
                              day: today,
                              status: s,
                              current: mine,
                              event: event,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
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
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label, this.color);
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        FittedBox(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
