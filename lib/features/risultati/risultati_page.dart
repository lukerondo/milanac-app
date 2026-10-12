import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import 'match.dart';
import 'match_detail_page.dart';
import 'match_editor.dart';
import 'matches_repository.dart';
import 'result_ui.dart';

/// Risultati (scheda di Partite): filtri per squadra e tipo, bilancio e l'elenco
/// delle partite con l'esito V / N / P, come la tavola delle Partite.
class RisultatiPage extends ConsumerStatefulWidget {
  const RisultatiPage({super.key});

  @override
  ConsumerState<RisultatiPage> createState() => _RisultatiPageState();
}

class _RisultatiPageState extends ConsumerState<RisultatiPage> {
  /// Squadra (null = tutte) e tipo di partita (null = ufficiali e amichevoli).
  Team? _team;
  MatchKind? _kind;

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final matches = ref.watch(matchesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              onPressed: () => showMatchEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuova partita'),
            )
          : null,
      body: AsyncView(
        value: matches,
        onRetry: () => ref.invalidate(matchesProvider),
        data: (all) {
          final list = all
              .where(
                (m) =>
                    (_kind == null || m.kind == _kind) &&
                    (_team == null || m.team == _team),
              )
              .toList();
          final record = MatchRecord(list);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in Team.values)
                    FilterPill(
                      label: teamPillLabel(t),
                      selected: _team == t,
                      onTap: () => setState(() => _team = t),
                    ),
                  FilterPill(
                    label: 'Tutte',
                    selected: _team == null,
                    onTap: () => setState(() => _team = null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Tipo: si tocca di nuovo per tornare a tutte le partite.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (label, kind) in [
                    ('Ufficiali', MatchKind.torneo),
                    ('Amichevoli', MatchKind.amichevole),
                  ])
                    FilterPill(
                      label: label,
                      square: true,
                      selected: _kind == kind,
                      onTap: () =>
                          setState(() => _kind = _kind == kind ? null : kind),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (record.played > 0) ...[
                _RecordCard(record: record),
                const SizedBox(height: 20),
              ],
              const SectionLabel('Ultimi risultati'),
              const SizedBox(height: 10),
              if (list.isEmpty)
                AppCard(
                  child: Text(
                    'Nessuna partita registrata.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.pal.textMuted,
                    ),
                  ),
                )
              else
                MatchList(matches: list),
            ],
          );
        },
      ),
    );
  }
}

/// Bilancio delle partite mostrate: giocate, vinte, pari, perse e gol.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final MatchRecord record;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cells = [
      ('${record.played}', 'Giocate', p.text),
      ('${record.wins}', 'Vinte', p.success),
      ('${record.draws}', 'Pari', p.textSecondary),
      ('${record.losses}', 'Perse', p.danger),
      ('${record.goalsFor}:${record.goalsAgainst}', 'Gol', p.accentText),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
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
                        fontFamily: sportFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 13, color: p.textMuted),
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

/// Apre il dettaglio di una partita sopra le schede.
void openMatch(BuildContext context, String matchId) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(builder: (_) => MatchDetailPage(matchId: matchId)));

/// Le partite in una card, una riga ciascuna, separate da un filetto.
class MatchList extends StatelessWidget {
  const MatchList({super.key, required this.matches});
  final List<ClubMatch> matches;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, m) in matches.indexed) ...[
          if (i > 0) const Divider(indent: 16, endIndent: 16),
          MatchRow(match: m),
        ],
      ],
    ),
  );
}

/// Riga di una partita: esito, avversario, competizione, punteggio e data.
class MatchRow extends ConsumerWidget {
  const MatchRow({super.key, required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    // Solo il numero: la riga non si ridisegna per i media delle altre partite.
    final mediaCount = ref.watch(
      matchMediaProvider(match.id).select((m) => m.value?.length ?? 0),
    );
    return InkWell(
      onTap: () => openMatch(context, match.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            OutcomeBadge(match.outcome),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.opponent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    matchSubtitle(match),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textMuted),
                  ),
                ],
              ),
            ),
            if (mediaCount > 0) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: mediaCount == 1
                    ? 'Un video o una foto'
                    : '$mediaCount video e foto',
                child: Icon(
                  Icons.play_circle_rounded,
                  size: 20,
                  color: p.accentText,
                ),
              ),
            ],
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  scoreText(match),
                  style: const TextStyle(
                    fontFamily: sportFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .6,
                    height: 1.15,
                  ),
                ),
                Text(
                  DateFormat('d MMM', 'it').format(match.playedAt),
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
