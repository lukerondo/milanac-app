import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import '../presenze/evening.dart';
import '../risultati/match.dart';
import '../risultati/match_detail_page.dart';
import '../risultati/matches_repository.dart';
import 'club_event.dart';
import 'event_editor.dart';
import 'events_repository.dart';

/// I prossimi [count] appuntamenti dopo [now] (un istante), dal più vicino: non si conta
/// sull'ordine in cui arrivano gli eventi.
List<ClubEvent> upcomingEvents(
  Iterable<ClubEvent> events,
  DateTime now, {
  int count = 5,
}) {
  final from = italianClock(now);
  return sortedByStart(events.where((e) => e.startsAt.isAfter(from)))
      .take(count)
      .toList();
}

/// Il giorno (italiano) di un evento.
DateTime _dayOf(ClubEvent e) =>
    DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);

/// Calendario (scheda di Partite): solo ciò che cambia rispetto all'allenamento di ogni
/// sera, questa settimana e più avanti, e gli ultimi risultati.
class CalendarioPage extends ConsumerStatefulWidget {
  const CalendarioPage({super.key});

  @override
  ConsumerState<CalendarioPage> createState() => _CalendarioPageState();
}

class _CalendarioPageState extends ConsumerState<CalendarioPage> {
  /// Squadra dei filtri (null = tutte); all'apertura quella del membro.
  late Team? _team = mainTeam(
    ref.read(profileProvider).value?.teams ?? const {Team.milanac},
  );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final events = ref.watch(eventsProvider);
    final matches = ref.watch(matchesProvider).value ?? const <ClubMatch>[];
    final now = ref.watch(clockProvider)();
    // Oggi in Italia: gli eventi sono già in ora italiana.
    final today = italianDay(now);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);

    bool shows(Team? team) => _team == null || team == null || team == _team;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              onPressed: () => showEventEditor(context, day: today),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuovo evento'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in [...Team.values, null])
                    FilterPill(
                      label: t == null ? 'Tutte' : teamTabLabel(t),
                      selected: _team == t,
                      onTap: () => setState(() => _team = t),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: events,
              onRetry: () => ref.invalidate(eventsProvider),
              data: (all) {
                final mine = [
                  for (final e in all)
                    if (shows(e.team)) e,
                ];
                final thisWeek = sortedByStart(
                  mine.where(
                    (e) =>
                        !_dayOf(e).isBefore(today) &&
                        _dayOf(e).isBefore(nextMonday),
                  ),
                );
                final later = upcomingEvents(
                  mine.where((e) => !_dayOf(e).isBefore(nextMonday)),
                  now,
                );
                final results =
                    matches
                        .where(
                          (m) =>
                              shows(m.team) &&
                              m.outcome != MatchOutcome.daGiocare,
                        )
                        .toList()
                      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    Text(
                      "Ogni sera c'è l'allenamento alle "
                      '${DateFormat('HH:mm').format(trainingOn(today).startsAt)}. '
                      'Qui trovi solo ciò che cambia.',
                      style: TextStyle(color: p.textSecondary, fontSize: 15),
                    ),
                    const SizedBox(height: 14),
                    const SectionLabel('Questa settimana'),
                    const SizedBox(height: 10),
                    _EventList(
                      events: thisWeek,
                      showTeam: _team == null,
                      editable: isDirettivo,
                      empty: 'Questa settimana solo gli allenamenti.',
                    ),
                    if (later.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const SectionLabel('Più avanti'),
                      const SizedBox(height: 10),
                      _EventList(
                        events: later,
                        showTeam: _team == null,
                        editable: isDirettivo,
                        showMonth: true,
                      ),
                    ],
                    if (results.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SectionLabel(
                        'Ultimi risultati',
                        trailing: TextButton(
                          onPressed: () =>
                              context.go('/partite?scheda=risultati'),
                          child: const Text('Tutti'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final (i, m) in results.take(3).indexed) ...[
                              if (i > 0)
                                Divider(
                                  indent: 16,
                                  endIndent: 16,
                                  color: p.divider,
                                ),
                              _ResultRow(match: m),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Gli eventi in una card, uno per riga, con la data in tessera.
class _EventList extends StatelessWidget {
  const _EventList({
    required this.events,
    required this.showTeam,
    required this.editable,
    this.showMonth = false,
    this.empty,
  });
  final List<ClubEvent> events;
  final bool showTeam;
  final bool editable;
  final bool showMonth;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (events.isEmpty) {
      return AppCard(
        child: Text(
          empty ?? '',
          style: TextStyle(color: p.textMuted, fontSize: 15),
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, e) in events.indexed) ...[
            if (i > 0) Divider(indent: 16, endIndent: 16, color: p.divider),
            EventRow(
              event: e,
              showTeam: showTeam,
              showMonth: showMonth,
              onTap: e.id.isEmpty
                  ? null
                  : () => showEventDetails(context, e, editable: editable),
            ),
          ],
        ],
      ),
    );
  }
}

/// Un evento: data in tessera, titolo, ora e tipo. Le partite ufficiali sono in
/// evidenza, con "Vedi formazione".
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.event,
    this.showTeam = false,
    this.showMonth = false,
    this.onTap,
  });
  final ClubEvent event;
  final bool showTeam;

  /// Il mese sotto il giorno (eventi lontani).
  final bool showMonth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final official = event.type == EventType.torneo;
    final dateColor = official ? p.accentText : p.text;
    final subtitle = [
      DateFormat('HH:mm').format(event.startsAt),
      event.type.label,
      if (showTeam && event.team != null) teamTabLabel(event.team!),
      if (event.location != null && event.location!.isNotEmpty) event.location!,
    ].join(' · ');
    return Material(
      color: official ? (p.isDark ? p.hero : p.accentTint) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Text(
                      DateFormat(
                        'E',
                        'it',
                      ).format(event.startsAt).toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: official ? p.accentText : p.textMuted,
                      ),
                    ),
                    Text(
                      '${event.startsAt.day}',
                      style: TextStyle(
                        fontFamily: sportFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 24,
                        height: 1.1,
                        color: dateColor,
                      ),
                    ),
                    if (showMonth)
                      Text(
                        DateFormat(
                          'MMM',
                          'it',
                        ).format(event.startsAt).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: official ? p.accentText : p.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                    if (official) ...[
                      // Il pulsante ha già 6 punti di margine per il tocco.
                      _GoldPill(
                        label: 'Vedi formazione',
                        onTap: () => context.push('/formazione'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pillola oro piena: l'azione principale della riga. Larga quanto il testo, alta 36
/// punti, ma si tocca su 48.
class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    child: Text(label),
  );
}

/// Un risultato: esito (V, N, P), avversario, competizione e punteggio.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = match;
    final (letter, label, fg, bg) = switch (m.outcome) {
      MatchOutcome.vittoria => ('V', 'Vittoria', p.success, p.successBg),
      MatchOutcome.pareggio => ('N', 'Pareggio', p.textSecondary, p.border),
      _ => ('P', 'Sconfitta', p.danger, p.dangerBg),
    };
    final subtitle = [
      m.competition?.replaceAll(' – ', ' · ') ?? m.kind.label,
      if (m.team == Team.futuro) 'Futuro',
      if (!m.home) 'in trasferta',
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => MatchDetailPage(matchId: m.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Semantics(
              label: label,
              excludeSemantics: true,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontFamily: sportFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: fg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.opponent,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: p.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${m.goalsFor} – ${m.goalsAgainst}',
              style: TextStyle(
                fontFamily: sportFont,
                fontWeight: FontWeight.w600,
                fontSize: 22,
                letterSpacing: .6,
                color: p.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
