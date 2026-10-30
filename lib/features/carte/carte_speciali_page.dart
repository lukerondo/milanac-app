import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart' show ContentWidth;
import '../../shared/async_view.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../carta/card_colors.dart';
import '../carta/carta_page.dart';
import '../risultati/match.dart';
import '../risultati/matches_repository.dart';
import '../risultati/result_ui.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'special_cards_repository.dart';

/// Le Carte speciali a tutto schermo, sopra la pagina aperta (dalla partita o dal
/// profilo): indietro si torna lì.
void openSpecialCards(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(
          appBar: _FullScreenBar(),
          body: ContentWidth(child: CarteSpecialiPage()),
        ),
      ),
    );

class _FullScreenBar extends StatelessWidget implements PreferredSizeWidget {
  const _FullScreenBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: const Text('CARTE SPECIALI'),
    flexibleSpace: const Align(
      alignment: Alignment.topCenter,
      child: GoldRule(),
    ),
  );
}

/// Sezione "Carte speciali": le carte della settimana (la blu elettrico e le nero/oro
/// per reparto) e lo storico per giornata, come la tavola.
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
    // Si ridisegna anche quando una carta scade (le carte valide si ricalcolano da sé).
    ref.watch(activeSpecialCardsProvider);
    final now = ref.watch(clockProvider)();
    final p = context.pal;
    return AsyncView(
      value: cards,
      onRetry: () => ref.invalidate(specialCardsProvider),
      data: (all) {
        final active = all.where((c) => c.activeAt(now)).toList()
          ..sort(compareCardsForDisplay);
        final past = all.where((c) => !c.activeAt(now)).toList()
          ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
        // Storico raggruppato per partita, dalla più recente.
        final groups = <String?, List<SpecialCard>>{};
        for (final c in past) {
          groups.putIfAbsent(c.matchId, () => []).add(c);
        }
        final blue = active.where((c) => c.isBlue).toList();
        final neroOro = active.where((c) => !c.isBlue).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _WeekHeader(cards: active, matches: matches, now: now),
            const SizedBox(height: 14),
            if (active.isEmpty) ...[
              AppCard(
                child: Text(
                  'Nessuna carta speciale in corso: si assegnano dal risultato '
                  'della prossima partita.',
                  style: TextStyle(fontSize: 15, color: p.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
            ],
            for (final c in blue) ...[
              _BlueCardRow(card: c, member: members[c.playerId]),
              const SizedBox(height: 14),
            ],
            if (neroOro.isNotEmpty) ...[
              _NeroOroSection(cards: neroOro, members: members),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 4),
            const SectionLabel('Storico'),
            const SizedBox(height: 8),
            if (groups.isEmpty)
              Text(
                'Le carte delle settimane passate compariranno qui.',
                style: TextStyle(fontSize: 15, color: p.textMuted),
              ),
            for (final MapEntry(key: matchId, value: list) in groups.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PastGroup(
                  match: matchId == null ? null : matches[matchId],
                  cards: list..sort(compareCardsForDisplay),
                  members: members,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Le nero/oro le sceglie il Direttivo dopo ogni giornata, una per '
              'reparto. La blu elettrico arriva da sola: tripletta o tre partite '
              'di fila senza subire gol. Durano 7 giorni.',
              style: TextStyle(fontSize: 14, height: 1.45, color: p.textMuted),
            ),
          ],
        );
      },
    );
  }
}

/// "QUESTA SETTIMANA · 2ª GIORNATA" e, sotto, la partita e quando scadono le carte.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.cards,
    required this.matches,
    required this.now,
  });
  final List<SpecialCard> cards;
  final Map<String, ClubMatch> matches;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // Le partite della settimana, ognuna con la sua scadenza.
    final byMatch = <String?, DateTime>{};
    for (final c in cards) {
      final end = byMatch[c.matchId];
      if (end == null || c.endsAt.isBefore(end)) byMatch[c.matchId] = c.endsAt;
    }
    final played = [
      for (final id in byMatch.keys)
        if (id != null && matches[id] != null) matches[id]!,
    ];
    final matchday = played.length == 1 ? matchdayOf(played.single) : null;
    final lines = [
      for (final MapEntry(key: id, value: end) in byMatch.entries)
        [
          if (id != null && matches[id] != null) matchTitle(matches[id]!),
          'scadono ${relativeDay(end, now)}',
        ].join(' · '),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          matchday == null
              ? 'Questa settimana'
              : 'Questa settimana · $matchday',
        ),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l,
              style: TextStyle(fontSize: 15, color: context.pal.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// Foto tonda con un anello colorato (o il tondo con le iniziali).
class _RingedPhoto extends StatelessWidget {
  const _RingedPhoto({
    required this.member,
    required this.ring,
    required this.size,
    this.ringWidth = 2,
  });
  final Member? member;
  final Color ring;
  final double size;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final inner = size / 2 - ringWidth;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
      child: m == null
          ? CircleAvatar(
              radius: inner,
              backgroundColor: CardColors.portrait,
              child: Icon(
                Icons.person_rounded,
                size: inner,
                color: CardColors.textMuted,
              ),
            )
          : MemberAvatar(
              member: m,
              radius: inner,
              background: CardColors.portrait,
              foreground: CardColors.text,
            ),
    );
  }
}

/// La carta blu elettrico: riga blu con foto, reparto, motivo e overall.
class _BlueCardRow extends StatelessWidget {
  const _BlueCardRow({required this.card, required this.member});
  final SpecialCard card;
  final Member? member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final overall = overallWith(m?.overall, card);
    return Material(
      color: CardColors.blue,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: m == null ? null : () => openPlayerCard(context, m.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _RingedPhoto(
                member: m,
                ring: CardColors.onBlue,
                size: 60,
                ringWidth: 3,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BLU ELETTRICO · ${card.reparto}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: CardColors.onBlue,
                      ),
                    ),
                    Text(
                      m?.displayName ?? 'Ex membro',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: CardColors.onBlue,
                      ),
                    ),
                    Text(
                      card.reason ??
                          'Tripletta o tre partite di fila senza subire gol',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: CardColors.onBlue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (overall != null)
                    Text(
                      '$overall',
                      style: const TextStyle(
                        fontFamily: sportFont,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: CardColors.onBlue,
                      ),
                    ),
                  Text(
                    '+${card.bonus}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: CardColors.onBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le nero/oro della settimana, una riga per reparto, sul fondo nero e oro.
class _NeroOroSection extends StatelessWidget {
  const _NeroOroSection({required this.cards, required this.members});
  final List<SpecialCard> cards;
  final Map<String, Member> members;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: CardColors.neroOro,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: CardColors.gold),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'NERO/ORO DELLA SETTIMANA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: CardColors.goldText,
            ),
          ),
        ),
        for (final (i, c) in cards.indexed) ...[
          if (i > 0)
            const Divider(
              color: CardColors.neroOroLine,
              indent: 16,
              endIndent: 16,
            ),
          _NeroOroRow(card: c, member: members[c.playerId]),
        ],
        const SizedBox(height: 4),
      ],
    ),
  );
}

class _NeroOroRow extends StatelessWidget {
  const _NeroOroRow({required this.card, required this.member});
  final SpecialCard card;
  final Member? member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final overall = overallWith(m?.overall, card);
    return InkWell(
      onTap: m == null ? null : () => openPlayerCard(context, m.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  card.reparto,
                  style: const TextStyle(
                    fontFamily: sportFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CardColors.goldText,
                  ),
                ),
              ),
              _RingedPhoto(member: m, ring: CardColors.gold, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  m?.displayName ?? 'Ex membro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: CardColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(
                  children: [
                    if (overall != null) TextSpan(text: '$overall '),
                    TextSpan(
                      text: '+${card.bonus}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontFamily: sportFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: CardColors.goldText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le carte di una giornata passata: si apre con un tocco.
class _PastGroup extends StatefulWidget {
  const _PastGroup({
    required this.match,
    required this.cards,
    required this.members,
  });
  final ClubMatch? match;
  final List<SpecialCard> cards;
  final Map<String, Member> members;

  @override
  State<_PastGroup> createState() => _PastGroupState();
}

class _PastGroupState extends State<_PastGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = widget.match;
    final cards = widget.cards;
    final title = [
      if (m != null)
        matchdayOf(m) ?? DateFormat('d MMMM', 'it').format(m.playedAt)
      else
        DateFormat('d MMMM yyyy', 'it').format(cards.first.startsAt),
      if (m != null) '${m.opponent} ${scoreText(m)}',
    ].join(' · ');
    String who(SpecialCard c) =>
        widget.members[c.playerId]?.displayName ?? 'Ex membro';
    final summary = cards.length == 1
        ? '1 carta: ${who(cards.single)}, ${cards.single.reparto} +${cards.single.bonus}'
        : '${cards.length} carte: '
              '${cards.map((c) => shortName(who(c))).join(', ')}';
    return AppCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
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
                            summary,
                            maxLines: _open ? 3 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_rounded, color: p.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Column(
                      children: [
                        for (final c in cards)
                          SpecialCardRow(
                            card: c,
                            member: widget.members[c.playerId],
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Riga compatta di una carta: tipo, reparto, giocatore, motivo e bonus.
class SpecialCardRow extends StatelessWidget {
  const SpecialCardRow({super.key, required this.card, required this.member});
  final SpecialCard card;
  final Member? member;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ink = CardColors.ink(p, isBlue: card.isBlue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(card.kind.icon, color: ink, size: 20),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              card.reparto,
              style: TextStyle(
                fontFamily: sportFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (card.reason != null)
                  Text(
                    card.reason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: p.textMuted),
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
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Milan AC 3 – 1 Dinamo Pixel": il club prima, con i suoi gol prima.
String matchTitle(ClubMatch m) {
  final us = m.team.label;
  if (m.outcome == MatchOutcome.daGiocare) return '$us – ${m.opponent}';
  return '$us ${scoreText(m)} ${m.opponent}';
}
