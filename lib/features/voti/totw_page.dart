import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import '../carta/carta_page.dart';
import '../carta/fut_card.dart';
import '../risultati/match_detail_page.dart';
import '../risultati/matches_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'ratings_repository.dart';

/// Reparti della Squadra della settimana, dall'attacco alla porta (come in FUT).
enum _Reparto {
  attacco('Attacco'),
  centrocampo('Centrocampo'),
  difesa('Difesa'),
  porta('Porta');

  const _Reparto(this.label);
  final String label;

  static _Reparto of(String? position) => switch (position) {
    'POR' => porta,
    'DC' || 'TD' || 'TS' => difesa,
    'ED' || 'ES' || 'AD' || 'AS' || 'ATT' => attacco,
    _ => centrocampo,
  };
}

/// Squadra della settimana: i migliori 11 per media voti, con le carte speciali.
class TotwPage extends ConsumerStatefulWidget {
  const TotwPage({super.key});

  @override
  ConsumerState<TotwPage> createState() => _TotwPageState();
}

class _TotwPageState extends ConsumerState<TotwPage> {
  Team _team = Team.milanac;

  /// Settimana scelta (lunedì); null = l'ultima con un Uomo partita.
  DateTime? _week;

  DateTime _defaultWeek(List<MvpAward> awards) {
    final mine = awards.where((a) => a.team == _team).toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return weekStart(mine.firstOrNull?.playedAt ?? DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final awards = ref.watch(mvpsProvider).value ?? const <MvpAward>[];
    final week = _week ?? _defaultWeek(awards);
    final thisWeek = weekStart(DateTime.now());
    final entries = ref.watch(totwProvider((week, _team)));
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final fmt = DateFormat('d MMM', 'it');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SegmentedButton<Team>(
          segments: [
            for (final t in Team.values)
              ButtonSegment(value: t, label: Text(t.short)),
          ],
          selected: {_team},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _team = s.first;
            _week = null;
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: 'Settimana precedente',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(
                () => _week = week.subtract(const Duration(days: 7)),
              ),
            ),
            Expanded(
              child: Text(
                'Settimana ${fmt.format(week)} – '
                '${fmt.format(week.add(const Duration(days: 6)))}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Settimana successiva',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: week.isBefore(thisWeek)
                  ? () => setState(
                      () => _week = week.add(const Duration(days: 7)),
                    )
                  : null,
            ),
          ],
        ),
        ...switch (entries) {
          AsyncData(:final value) when value.isEmpty => [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Text(
                'Nessun voto in questa settimana.\n'
                'Si vota dalla pagina di ogni partita, in Risultati.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
          AsyncData(:final value) => [
            for (final reparto in _Reparto.values)
              if (value.any(
                (e) =>
                    _Reparto.of(members[e.playerId]?.fieldPosition) == reparto,
              )) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(
                    reparto.label.toUpperCase(),
                    style: const TextStyle(
                      color: MilanacColors.gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in value)
                      if (members[e.playerId] case final m?
                          when _Reparto.of(m.fieldPosition) == reparto)
                        _TotwCard(member: m, entry: e),
                  ],
                ),
              ],
          ],
          AsyncError(:final error) => [Text('Errore: $error')],
          _ => [
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        },
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 24, 4, 6),
          child: Text(
            'ULTIMI UOMINI PARTITA',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ),
        _RecentMvps(awards: awards, members: members),
      ],
    );
  }
}

class _TotwCard extends ConsumerWidget {
  const _TotwCard({required this.member, required this.entry});
  final Member member;
  final TotwEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(cardStatsProvider(member.id));
    final width = (MediaQuery.sizeOf(context).width - 32 - 20) / 3;
    return SizedBox(
      width: width.clamp(90, 140),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => PlayerCardPage(memberId: member.id),
              ),
            ),
            child: stats == null
                ? const AspectRatio(aspectRatio: 300 / 428)
                : FutCard(
                    member: member,
                    stats: stats,
                    special: CardSpecial.totw,
                  ),
          ),
          Text(
            entry.average.toStringAsFixed(1),
            style: const TextStyle(
              color: MilanacColors.gold,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentMvps extends ConsumerWidget {
  const _RecentMvps({required this.awards, required this.members});
  final List<MvpAward> awards;
  final Map<String, Member> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = {
      for (final m in ref.watch(matchesProvider).value ?? const []) m.id: m,
    };
    final recent = [...awards]
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    if (recent.isEmpty) {
      return const Text(
        'Ancora nessuno: serve almeno una partita con 2 voti.',
        style: TextStyle(color: Colors.white54),
      );
    }
    return Column(
      children: [
        for (final a in recent.take(6))
          if (members[a.playerId] case final m?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.emoji_events_rounded,
                color: MilanacColors.gold,
              ),
              title: Text(m.displayName),
              subtitle: Text(
                [
                  DateFormat('d MMM', 'it').format(a.playedAt),
                  if (matches[a.matchId] case final match?)
                    'vs ${match.opponent}',
                  a.team.short,
                ].join(' · '),
              ),
              trailing: Text(
                a.average.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: MilanacColors.gold,
                ),
              ),
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => MatchDetailPage(matchId: a.matchId),
                ),
              ),
            ),
      ],
    );
  }
}
