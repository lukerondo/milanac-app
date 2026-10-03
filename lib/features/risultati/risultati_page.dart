import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import 'match.dart';
import 'match_detail_page.dart';
import 'match_editor.dart';
import 'matches_repository.dart';

Color outcomeColor(MatchOutcome o) => switch (o) {
  MatchOutcome.vittoria => const Color(0xFF2E9E5B),
  MatchOutcome.pareggio => const Color(0xFFE0A526),
  MatchOutcome.sconfitta => MilanacColors.red,
  MatchOutcome.daGiocare => Colors.white38,
};

class RisultatiPage extends ConsumerStatefulWidget {
  const RisultatiPage({super.key});

  @override
  ConsumerState<RisultatiPage> createState() => _RisultatiPageState();
}

class _RisultatiPageState extends ConsumerState<RisultatiPage> {
  MatchKind? _filter;
  Team? _team;

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final matches = ref.watch(matchesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () => showMatchEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuova partita'),
            )
          : null,
      body: matches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore nel caricamento: $e')),
        data: (all) {
          final list = all
              .where(
                (m) =>
                    (_filter == null || m.kind == _filter) &&
                    (_team == null || m.team == _team),
              )
              .toList();
          final record = MatchRecord(list);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Wrap(
                children: [
                  for (final (label, kind) in [
                    ('Tutte', null),
                    ('Tornei', MatchKind.torneo),
                    ('Amichevoli', MatchKind.amichevole),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == kind,
                        onSelected: (_) => setState(() => _filter = kind),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TeamFilter(
                value: _team,
                onChanged: (t) => setState(() => _team = t),
              ),
              const SizedBox(height: 8),
              _RecordCard(record: record),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'Nessuna partita registrata.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              for (final m in list) MatchCard(match: m),
            ],
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final MatchRecord record;

  @override
  Widget build(BuildContext context) {
    final cells = [
      ('${record.played}', 'Giocate', Colors.white),
      ('${record.wins}', 'Vinte', outcomeColor(MatchOutcome.vittoria)),
      ('${record.draws}', 'Pari', outcomeColor(MatchOutcome.pareggio)),
      ('${record.losses}', 'Perse', outcomeColor(MatchOutcome.sconfitta)),
      ('${record.goalsFor}:${record.goalsAgainst}', 'Gol', MilanacColors.gold),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            for (final (value, label, color) in cells)
              Expanded(
                child: Column(
                  children: [
                    FittedBox(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ),
                    FittedBox(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MatchCard extends ConsumerWidget {
  const MatchCard({super.key, required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(matchMediaProvider(match.id)).value ?? const [];
    final color = outcomeColor(match.outcome);
    final score = match.outcome == MatchOutcome.daGiocare
        ? '– : –'
        : match.home
        ? '${match.goalsFor} : ${match.goalsAgainst}'
        : '${match.goalsAgainst} : ${match.goalsFor}';
    final us = match.team.label;
    final home = match.home ? us : match.opponent;
    final away = match.home ? match.opponent : us;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => MatchDetailPage(matchId: match.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: match.kind == MatchKind.torneo
                          ? MilanacColors.red
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      match.kind.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        if (match.competition != null) match.competition!,
                        DateFormat('d MMM yyyy', 'it').format(match.playedAt),
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (media.isNotEmpty) ...[
                    const Icon(
                      Icons.perm_media_rounded,
                      size: 16,
                      color: MilanacColors.gold,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${media.length}',
                      style: const TextStyle(
                        color: MilanacColors.gold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      home,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: _teamStyle(match.home),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      border: Border.all(color: color),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      score,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      away,
                      overflow: TextOverflow.ellipsis,
                      style: _teamStyle(!match.home),
                    ),
                  ),
                ],
              ),
              if (match.scorers != null && match.scorers!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.sports_soccer_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        match.scorers!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static TextStyle _teamStyle(bool us) => TextStyle(
    fontWeight: FontWeight.w800,
    color: us ? MilanacColors.gold : Colors.white,
  );
}
