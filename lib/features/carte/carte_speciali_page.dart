import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/theme.dart';
import '../carta/carta_page.dart';
import '../carta/fut_card.dart';
import '../risultati/match.dart';
import '../risultati/matches_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'special_cards_repository.dart';

/// Sezione "Carte speciali": le carte della settimana e lo storico per giornata.
class CarteSpecialiPage extends ConsumerWidget {
  const CarteSpecialiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(specialCardsProvider);
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final matches = {
      for (final m in ref.watch(matchesProvider).value ?? const <ClubMatch>[])
        m.id: m,
    };
    final now = ref.watch(clockProvider)();
    return cards.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (all) {
        final active = all.where((c) => c.activeAt(now)).toList()
          ..sort(compareCards);
        final past = all.where((c) => !c.activeAt(now)).toList()
          ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
        // Storico raggruppato per partita, dalla più recente.
        final groups = <String?, List<SpecialCard>>{};
        for (final c in past) {
          groups.putIfAbsent(c.matchId, () => []).add(c);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _Intro(),
            const _Header('Questa settimana', icon: Icons.military_tech_rounded),
            if (active.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nessuna carta speciale in corso: si assegnano dal risultato della prossima partita.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              _ActiveGrid(cards: active, members: members),
            const _Header('Storico', icon: Icons.history_rounded),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Le carte delle settimane passate compariranno qui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            for (final MapEntry(key: matchId, value: list) in groups.entries)
              _PastGroup(
                match: matchId == null ? null : matches[matchId],
                cards: list..sort(compareCards),
                members: members,
              ),
          ],
        );
      },
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IntroRow(
            CardSpecial.neroOro,
            'Ogni settimana il Direttivo premia dal risultato un giocatore per reparto: '
            'carta nero/oro con bonus da +1 a +5 sull\'overall.',
          ),
          SizedBox(height: 8),
          _IntroRow(
            CardSpecial.blu,
            'La blu elettrico arriva da sola: tripletta, o tre partite ufficiali di fila '
            'senza subire gol per il portiere. Vale +5 e batte la nero/oro.',
          ),
          SizedBox(height: 8),
          Text(
            'Le carte speciali durano 7 giorni e sostituiscono quella normale ovunque.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _IntroRow extends StatelessWidget {
  const _IntroRow(this.kind, this.text);
  final CardSpecial kind;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(kind.icon, color: kind.color, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(height: 1.3))),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header(this.title, {required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: MilanacColors.red),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Le carte in corso: una carta FUT speciale per ogni premiato, due per riga.
class _ActiveGrid extends ConsumerWidget {
  const _ActiveGrid({required this.cards, required this.members});
  final List<SpecialCard> cards;
  final Map<String, Member> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 10,
      childAspectRatio: 300 / 500,
    ),
    itemCount: cards.length,
    itemBuilder: (context, i) {
      final c = cards[i];
      final m = members[c.playerId];
      final stats = m == null ? null : ref.watch(cardStatsProvider(m.id));
      return Column(
        children: [
          Expanded(
            child: m == null || stats == null
                ? const Center(child: Text('Ex membro'))
                : GestureDetector(
                    onTap: () => openPlayerCard(context, m.id),
                    child: FutCard(
                      member: m,
                      stats: stats,
                      special: c.kind,
                      bonus: c.bonus,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            '${c.reparto} · ${m?.displayName ?? '?'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            '${c.kind.label} +${c.bonus} · fino al ${DateFormat('d MMM', 'it').format(c.endsAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.kind.color, fontSize: 12),
          ),
        ],
      );
    },
  );
}

/// Le carte di una partita passata.
class _PastGroup extends StatelessWidget {
  const _PastGroup({
    required this.match,
    required this.cards,
    required this.members,
  });
  final ClubMatch? match;
  final List<SpecialCard> cards;
  final Map<String, Member> members;

  @override
  Widget build(BuildContext context) {
    final first = cards.first;
    final title = match == null
        ? DateFormat('d MMMM yyyy', 'it').format(first.startsAt)
        : matchTitle(match!);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: MilanacColors.gold,
              ),
            ),
            if (match?.competition != null)
              Text(
                match!.competition!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            const SizedBox(height: 6),
            for (final c in cards) SpecialCardRow(card: c, member: members[c.playerId]),
          ],
        ),
      ),
    );
  }
}

/// Riga compatta di una carta: tipo, reparto, giocatore, bonus e motivo.
class SpecialCardRow extends StatelessWidget {
  const SpecialCardRow({super.key, required this.card, required this.member});
  final SpecialCard card;
  final Member? member;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(card.kind.icon, color: card.kind.color, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            card.reparto,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white70,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member?.displayName ?? 'Ex membro',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (card.reason != null)
                Text(
                  card.reason!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
            ],
          ),
        ),
        Text(
          '+${card.bonus}',
          style: TextStyle(
            fontFamily: sportFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: card.kind.color,
          ),
        ),
      ],
    ),
  );
}

/// "Milan AC 3–1 Dinamo Pixel" (o in trasferta "Dinamo Pixel 1–3 Milan AC").
String matchTitle(ClubMatch m) {
  final us = m.team.label;
  if (m.outcome == MatchOutcome.daGiocare) return '$us – ${m.opponent}';
  return m.home
      ? '$us ${m.goalsFor}–${m.goalsAgainst} ${m.opponent}'
      : '${m.opponent} ${m.goalsAgainst}–${m.goalsFor} $us';
}
