import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../carte/special_cards_repository.dart';
import '../news/news_item.dart';
import '../news/news_page.dart';
import '../news/news_repository.dart';
import '../presenze/attendance.dart';
import '../presenze/attendance_repository.dart';
import '../presenze/attendance_ui.dart';
import '../presenze/evening.dart';
import '../presenze/presenze_page.dart';
import '../risultati/match.dart';
import '../risultati/match_detail_page.dart';
import '../risultati/matches_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

/// La Home: la serata di oggi per prima, poi la prossima partita, l'ultimo
/// risultato e Mondo Proclub.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final me = ref.watch(profileProvider).value;
    // La data di oggi in Italia.
    final today = italianDay(ref.watch(clockProvider)());
    final date = DateFormat('EEEE d MMMM', 'it').format(today);
    final name = (me?.firstName?.trim().isNotEmpty ?? false)
        ? me!.firstName!.trim()
        : (me?.displayName.trim().split(' ').first ?? '');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          '${date[0].toUpperCase()}${date.substring(1)}',
          style: TextStyle(color: p.textMuted, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          name.isEmpty ? 'CIAO' : 'CIAO, ${name.toUpperCase()}',
          style: TextStyle(
            fontFamily: sportFont,
            fontWeight: FontWeight.w600,
            fontSize: 28,
            letterSpacing: .8,
            color: p.text,
          ),
        ),
        const SizedBox(height: 16),
        const TonightCard(),
        const SizedBox(height: 16),
        const NextMatchCard(),
        const LastResultCard(),
        const MondoPanel(),
      ],
    );
  }
}

/// Titolo di una card (Oswald 18-24, maiuscolo).
TextStyle _cardTitle(AppPalette p, {double size = 20}) => TextStyle(
  fontFamily: sportFont,
  fontWeight: FontWeight.w600,
  fontSize: size,
  letterSpacing: size * .02,
  color: p.text,
);

// ------------------------------------------------------------------ stasera

/// La serata di oggi per la squadra del membro: la sua risposta e i conteggi.
class TonightCard extends ConsumerWidget {
  const TonightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final me = ref.watch(profileProvider).value;
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final attendance = ref.watch(attendanceProvider);
    final rosa = ref.watch(rosaProvider);
    final now = ref.watch(clockProvider)();
    // Stasera in Italia, come sul server (anche la scadenza delle 18:30).
    final today = italianDay(now);
    final myTeams = me?.teams ?? const {Team.milanac};
    final event = eveningEvent(events, today, teams: myTeams);
    final team = event.team ?? mainTeam(myTeams);

    void retry() {
      ref.invalidate(rosaProvider);
      ref.invalidate(attendanceProvider);
    }

    return AppCard(
      important: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Stasera · ${team.label}', gold: true),
          const SizedBox(height: 2),
          Text(
            '${event.type.label.toUpperCase()} '
            '${DateFormat('HH:mm').format(event.startsAt)}',
            style: _cardTitle(p, size: 24),
          ),
          if (event.title != event.type.label)
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textSecondary, fontSize: 15),
            ),
          AsyncView(
            value: rosa,
            onRetry: retry,
            data: (all) => AsyncView(
              value: attendance,
              onRetry: retry,
              data: (entries) => _Tonight(
                me: me,
                members: [
                  for (final m in all)
                    if (m.active &&
                        m.role != ClubRole.pending &&
                        m.teams.contains(team))
                      m,
                ],
                tonight: {
                  for (final e in entries.where((e) => e.date == today))
                    e.playerId: e,
                },
                today: today,
                open: answersOpen(today, now),
                event: event,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La propria risposta per stasera e i conteggi della squadra.
class _Tonight extends ConsumerWidget {
  const _Tonight({
    required this.me,
    required this.members,
    required this.tonight,
    required this.today,
    required this.open,
    required this.event,
  });
  final Profile? me;
  final List<Member> members;
  final Map<String, AttendanceEntry> tonight;
  final DateTime today;
  final bool open;
  final ClubEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final me = this.me;
    final mine = me == null ? null : tonight[me.id];
    final isMember = me != null && members.any((m) => m.id == me.id);
    final counts = DayCounts(members.map((m) => m.id), tonight);

    final status = !isMember
        ? null
        : mine != null
        ? 'La tua risposta: ${describeAttendance(mine)}'
              '${open ? ' · modificabile fino alle $attendanceDeadlineLabel' : ''}'
        : open
        ? 'Ci sei? Rispondi entro le $attendanceDeadlineLabel.'
        : 'Risposte chiuse alle $attendanceDeadlineLabel: chi non ha risposto risulta assente.';

    TextSpan number(int n) => TextSpan(
      text: '$n',
      style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null)
          Text(status, style: TextStyle(color: p.textSecondary, fontSize: 15)),
        if (isMember) ...[
          const SizedBox(height: 14),
          AttendanceButtons(
            selected: mine?.status,
            onAnswer: open
                ? (s) => answerAttendance(
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
        ],
        const SizedBox(height: 14),
        Divider(color: p.border, height: 1),
        Semantics(
          button: true,
          label: 'Apri le presenze',
          child: InkWell(
            onTap: () => context.go('/presenze'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 15,
                          ),
                          children: [
                            number(counts.present),
                            const TextSpan(text: ' presenti · '),
                            number(counts.late),
                            const TextSpan(text: ' in ritardo · '),
                            if (counts.absent > 0) ...[
                              number(counts.absent),
                              const TextSpan(text: ' assenti · '),
                            ],
                            number(counts.waiting),
                            const TextSpan(text: ' senza risposta'),
                          ],
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ partite

/// La prossima partita (ufficiale o amichevole) delle squadre del membro.
class NextMatchCard extends ConsumerWidget {
  const NextMatchCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final me = ref.watch(profileProvider).value;
    // Gli orari degli eventi sono in ora italiana.
    final now = italianClock(ref.watch(clockProvider)());
    final myTeams = me?.teams ?? const {Team.milanac};
    final next =
        (ref.watch(eventsProvider).value ?? const <ClubEvent>[])
            .where(
              (e) =>
                  e.type.isMatch &&
                  e.concerns(myTeams) &&
                  e.startsAt.isAfter(now.subtract(const Duration(hours: 3))),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final event = next.firstOrNull;
    if (event == null) return const SizedBox.shrink();
    final team = event.team ?? mainTeam(myTeams);
    final headline = matchHeadline(event, team);
    final when = DateFormat("EEEE d MMMM, HH:mm", 'it').format(event.startsAt);
    final kind = event.type == EventType.torneo ? 'Torneo' : 'Amichevole';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              'Prossima partita · $kind'
              '${myTeams.length > 1 ? ' · ${teamTabLabel(team)}' : ''}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Image.asset('assets/images/stemma_256.png', height: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline.title.toUpperCase(), style: _cardTitle(p)),
                      Text(
                        [?headline.detail, when].join(' · '),
                        style: TextStyle(color: p.textSecondary, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      textStyle: const TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => context.go('/formazione'),
                    child: const Text('Formazione'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      textStyle: const TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => context.go('/partite?scheda=calendario'),
                    child: const Text('Calendario'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// L'ultimo risultato delle squadre del membro, in evidenza: punteggio, marcatori e
/// carte speciali assegnate.
class LastResultCard extends ConsumerWidget {
  const LastResultCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final myTeams = me?.teams ?? const {Team.milanac};
    final played =
        (ref.watch(matchesProvider).value ?? const <ClubMatch>[])
            .where(
              (m) =>
                  myTeams.contains(m.team) &&
                  m.outcome != MatchOutcome.daGiocare,
            )
            .toList()
          ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final m = played.firstOrNull;
    if (m == null) return const SizedBox.shrink();
    final cards = (ref.watch(specialCardsProvider).value ?? const [])
        .where((c) => c.matchId == m.id)
        .length;
    // La card "hero" è scura anche nel tema chiaro: i colori degli esiti sono quelli
    // del tema scuro.
    const dark = AppPalette.dark;
    final (label, fg, bg) = switch (m.outcome) {
      MatchOutcome.vittoria => ('Vittoria', dark.success, dark.successBg),
      MatchOutcome.pareggio => ('Pareggio', dark.textSecondary, dark.border),
      _ => ('Sconfitta', dark.danger, dark.dangerBg),
    };
    final round = m.competition == null
        ? m.kind.label
        : m.competition!.split('–').last.trim();
    final us = m.team.label.toUpperCase();
    final them = m.opponent.toUpperCase();
    final (home, away) = m.home ? (us, them) : (them, us);
    final score = m.home
        ? '${m.goalsFor} – ${m.goalsAgainst}'
        : '${m.goalsAgainst} – ${m.goalsFor}';
    final details = [
      if ((m.scorers ?? '').trim().isNotEmpty) 'Gol: ${m.scorers!.trim()}',
      if (cards == 1) '1 carta speciale assegnata',
      if (cards > 1) '$cards carte speciali assegnate',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        label:
            'Ultimo risultato: ${m.team.label} ${m.goalsFor}, '
            '${m.opponent} ${m.goalsAgainst}',
        child: AppCard(
          hero: true,
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => MatchDetailPage(matchId: m.id),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'ULTIMO RISULTATO · ${round.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HeroText.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _teamName(home)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      score,
                      style: const TextStyle(
                        fontFamily: sportFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 40,
                        letterSpacing: 2,
                        color: HeroText.accent,
                      ),
                    ),
                  ),
                  Expanded(child: _teamName(away, end: true)),
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HeroText.secondary,
                    fontSize: 15,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _teamName(String name, {bool end = false}) => Text(
    name,
    textAlign: end ? TextAlign.right : TextAlign.left,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontFamily: sportFont,
      fontWeight: FontWeight.w600,
      fontSize: 18,
      letterSpacing: .4,
      color: HeroText.primary,
    ),
  );
}

// ------------------------------------------------------------------ Mondo Proclub

/// Mondo Proclub in breve: gli aggiornamenti da fare prima della partita e
/// l'ultimo video.
class MondoPanel extends ConsumerWidget {
  const MondoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final me = ref.watch(profileProvider).value;
    final videos = ref.watch(sharedLinksProvider(LinkCategory.video)).value;
    final news = ref.watch(newsProvider).value ?? const <NewsItem>[];
    final now = DateTime.now();

    final latest =
        (videos ?? const <SharedLink>[]).where((l) => l.isPublished).toList()
          ..sort(
            (a, b) => (b.publishedAt ?? b.createdAt ?? DateTime(2000))
                .compareTo(a.publishedAt ?? a.createdAt ?? DateTime(2000)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('MONDO PROCLUB', style: _cardTitle(p))),
            TextButton(
              onPressed: () => context.go('/mondo'),
              child: const Text('Vedi tutto'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (gameUpdate != null) ...[
          _UpdateRow(
            item: gameUpdate,
            title: 'Aggiorna FC 27 prima della partita',
          ),
          const SizedBox(height: 10),
        ],
        if (consoleUpdate != null) ...[
          _UpdateRow(
            item: consoleUpdate,
            title:
                'Aggiorna la ${platformLabel(consoleUpdate.platform)} prima della partita',
          ),
          const SizedBox(height: 10),
        ],
        if (video != null)
          _LatestVideo(video: video)
        else
          AppCard(
            radius: 16,
            child: Text(
              'Nessun video ancora: proponine uno al Direttivo.',
              style: TextStyle(color: p.textMuted, fontSize: 15),
            ),
          ),
      ],
    );
  }
}

/// Un aggiornamento da fare (gioco o console): conta oggi, quindi bordo oro.
class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.item, required this.title});
  final NewsItem item;
  final String title;

  @override
  Widget build(BuildContext context) => AppCard(
    important: true,
    radius: 16,
    padding: const EdgeInsets.all(14),
    onTap: () => openNews(item.url),
    child: Row(
      children: [
        const IconTile(Icons.download_rounded, solid: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: context.pal.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// L'ultimo video pubblicato: anteprima grande con il pulsante oro e il titolo.
class _LatestVideo extends StatelessWidget {
  const _LatestVideo({required this.video});
  final SharedLink video;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final id = youtubeId(video.url);
    final placeholder = ColoredBox(color: p.surfaceHigh);
    return AppCard(
      radius: 16,
      padding: EdgeInsets.zero,
      onTap: () => openSharedLink(video.url),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 168,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (id == null)
                  placeholder
                else
                  Image.network(
                    'https://img.youtube.com/vi/$id/mqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
                Center(
                  child: SizedBox.square(
                    dimension: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 30,
                        color: p.onAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Ultimo video'),
                const SizedBox(height: 2),
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
