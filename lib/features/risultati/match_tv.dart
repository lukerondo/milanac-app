import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/clock.dart';
import '../../core/italian_time.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../carta/card_colors.dart';
import '../carta/card_stats.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'match.dart';
import 'result_ui.dart';

/// La partita come in una diretta TV: il tabellone in testa e la cronaca minuto per
/// minuto. Sempre scuri (come la grafica delle dirette), anche nel tema chiaro.

/// I giocatori della squadra della partita (attivi, non in attesa): tra loro si
/// riconoscono i marcatori, come per i gol della carta.
List<Member> matchPlayers(Iterable<Member> roster, ClubMatch match) => [
  for (final m in roster)
    if (m.active && m.role != ClubRole.pending && m.teams.contains(match.team))
      m,
];

/// Sotto la squadra nel tabellone: i marcatori per cognome con i minuti ("Rossi 52'
/// 67'"); i gol senza minuto si aggiungono ("Neri 20' +1") o restano col nome ("Gialli",
/// "Gialli ×2").
List<String> scorerTicker(ClubMatch match, Iterable<Member> players) {
  final minutes = <String, List<int>>{};
  final names = <String, String>{};
  for (final g in match.timeline) {
    if (!g.ours) continue;
    final written = g.scorer ?? '';
    final member = written.isEmpty ? null : scorerMember(written, players);
    final key = member?.id ?? written.toLowerCase();
    (minutes[key] ??= []).add(g.minute);
    names[key] ??= member != null
        ? shortName(member.displayName)
        : (written.isEmpty ? 'Gol' : written);
  }
  final order = [...minutes.keys];
  final missing = <String, int>{};
  for (final (shown, goals, member) in scorerLines(match.scorers, players)) {
    final key = member?.id ?? shown.toLowerCase();
    final extra = goals - (minutes[key]?.length ?? 0);
    if (extra <= 0) continue;
    missing[key] = extra;
    names[key] ??= member == null ? shown : shortName(member.displayName);
    if (!minutes.containsKey(key)) order.add(key);
  }
  return [
    for (final key in order)
      [
        names[key]!,
        for (final m in minutes[key] ?? const <int>[]) "$m'",
        if ((missing[key] ?? 0) > 0 && minutes.containsKey(key))
          '+${missing[key]}',
        if ((missing[key] ?? 0) > 1 && !minutes.containsKey(key))
          '×${missing[key]}',
      ].join(' '),
  ];
}

/// Testata della partita come il tabellone delle dirette: competizione, stemmi e nomi,
/// il punteggio nelle caselle con "FINALE" sotto, i marcatori con i minuti sotto ogni
/// squadra e l'esito.
class TvScoreHeader extends ConsumerWidget {
  const TvScoreHeader({super.key, required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La testata è sempre scura: stati con la tavolozza scura anche nel tema chiaro.
    const dark = AppPalette.dark;
    final now = ref.watch(clockProvider)();
    final played = match.outcome != MatchOutcome.daGiocare;
    final (fg, bg) = outcomeColors(dark, match.outcome);
    final label = [
      competitionLabel(match),
      if (!match.home) 'in trasferta',
    ].join(' · ');
    // L'orario della partita è già in ora italiana; relativeDay vuole l'istante.
    final when = played
        ? '${outcomeLabel(match.outcome)} · '
              '${relativeDay(fromItalianClock(match.playedAt), now)}'
        : 'Da giocare · ${DateFormat("EEEE d MMMM, HH:mm", 'it').format(match.playedAt)}';
    final players = matchPlayers(
      ref.watch(rosaProvider).value ?? const [],
      match,
    );
    final against = [
      for (final g in match.timeline)
        if (!g.ours) "${g.minute}'",
    ];
    return ColoredBox(
      color: context.pal.hero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: HeroText.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TeamSide(
                    name: match.team.label,
                    badge: const ClubCrest(),
                    scorers: played ? scorerTicker(match, players) : const [],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _ScoreBoxes(match: match),
                ),
                Expanded(
                  child: _TeamSide(
                    name: match.opponent,
                    badge: _OpponentBadge(name: match.opponent),
                    scorers: against.isEmpty ? const [] : [against.join(' ')],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StatusPill(when, color: fg, background: bg, fontSize: 14),
          ],
        ),
      ),
    );
  }
}

/// Stemma, nome e marcatori di una squadra nel tabellone.
class _TeamSide extends StatelessWidget {
  const _TeamSide({
    required this.name,
    required this.badge,
    this.scorers = const [],
  });
  final String name;
  final Widget badge;
  final List<String> scorers;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      badge,
      const SizedBox(height: 6),
      Text(
        name.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: sportFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: .5,
          height: 1.2,
          color: HeroText.primary,
        ),
      ),
      for (final s in scorers)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.sports_soccer_rounded,
                size: 13,
                color: HeroText.secondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  s,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: HeroText.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Il tondo con le iniziali dell'avversario.
class _OpponentBadge extends StatelessWidget {
  const _OpponentBadge({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 60,
    height: 60,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: CardColors.portrait,
    ),
    child: Text(
      initialsOf(name),
      style: const TextStyle(
        fontFamily: sportFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: HeroText.secondary,
      ),
    ),
  );
}

/// Il punteggio nelle caselle del tabellone con "FINALE" sotto (o l'ora, se si deve
/// ancora giocare); entra con un piccolo rimbalzo.
class _ScoreBoxes extends StatelessWidget {
  const _ScoreBoxes({required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context) {
    final played = match.outcome != MatchOutcome.daGiocare;
    Widget box(String text) => Container(
      constraints: const BoxConstraints(minWidth: 50),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MilanacColors.surfaceHigh, MilanacColors.black],
        ),
        border: Border.all(color: MilanacColors.gold.withValues(alpha: .6)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: sportFont,
          fontSize: 42,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: HeroText.primary,
        ),
      ),
    );
    return Semantics(
      label: played
          ? 'Risultato: ${match.goalsFor} a ${match.goalsAgainst}'
          : 'Da giocare',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: .85 + .15 * t, child: child),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: played
                  ? [
                      box('${match.goalsFor}'),
                      const SizedBox(width: 4),
                      box('${match.goalsAgainst}'),
                    ]
                  : [box('VS')],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: MilanacColors.gold,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                played ? 'FINALE' : DateFormat('HH:mm').format(match.playedAt),
                style: const TextStyle(
                  fontFamily: sportFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: MilanacColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La partita minuto per minuto, come in una diretta: la linea del tempo con i gol (i
/// nostri sopra, quelli subiti sotto) e la cronaca dal calcio d'inizio al fischio
/// finale, con il punteggio dopo ogni gol. La nota della partita chiude la cronaca.
class MatchTimelineCard extends ConsumerWidget {
  const MatchTimelineCard({super.key, required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = matchPlayers(
      ref.watch(rosaProvider).value ?? const [],
      match,
    );
    final goals = match.timeline;
    // Il punteggio dopo ogni gol solo con tutti i minuti: con uno mancante sarebbe sbagliato.
    final complete =
        goals.where((g) => g.ours).length == (match.goalsFor ?? 0) &&
        goals.where((g) => !g.ours).length == (match.goalsAgainst ?? 0);
    final scores = runningScore(goals);
    final end = goals.fold(90, (m, g) => math.max(m, g.minute));
    final firstHalf = goals.where((g) => g.minute <= 45).length;
    final note = match.notes?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        hero: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CRONACA',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: HeroText.accent,
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: _TimeBar(goals: goals, end: end),
            ),
            const _Moment(minute: 0, text: "Calcio d'inizio"),
            for (final (i, g) in goals.indexed) ...[
              if (i == firstHalf) const _Moment(minute: 45, text: 'Intervallo'),
              _GoalMoment(
                goal: g,
                match: match,
                member: g.ours && g.scorer != null
                    ? scorerMember(g.scorer!, players)
                    : null,
                score: complete ? scores[i] : null,
              ),
            ],
            if (firstHalf == goals.length)
              const _Moment(minute: 45, text: 'Intervallo'),
            _Moment(
              minute: end,
              text: 'Fischio finale',
              trailing: scoreText(match),
            ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '«$note»',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: HeroText.secondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Linea del tempo dal calcio d'inizio a [end]: i gol del club sopra (oro), quelli
/// subiti sotto, con il minuto; l'intervallo a metà.
class _TimeBar extends StatelessWidget {
  const _TimeBar({required this.goals, required this.end});
  final List<MatchGoal> goals;
  final int end;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 76,
    child: LayoutBuilder(
      builder: (context, box) {
        const pad = 14.0, mid = 38.0;
        final w = box.maxWidth - 2 * pad;
        double x(int minute) => pad + w * minute / end;
        // Due gol vicini dalla stessa parte: l'etichetta del secondo si sposta di una
        // riga (verso l'esterno), quella del terzo torna al suo posto.
        final lift = List<double>.filled(goals.length, 0);
        final previous = <bool, int>{};
        for (final (i, g) in goals.indexed) {
          final j = previous[g.ours];
          if (j != null && x(g.minute) - x(goals[j].minute) < 30) {
            lift[i] = lift[j] == 0 ? 12 : 0;
          }
          previous[g.ours] = i;
        }
        const label = TextStyle(
          fontFamily: sportFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: pad,
              right: pad,
              top: mid - 1,
              height: 2,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: MilanacColors.goldDeep),
              ),
            ),
            for (final minute in [0, 45, 90, if (end > 90) end])
              Positioned(
                left: x(minute) - 1,
                top: mid - 6,
                width: 2,
                height: 12,
                child: const ColoredBox(color: MilanacColors.goldDeep),
              ),
            for (final (minute, text) in [
              (0, "0'"),
              (45, 'INT'),
              if (end <= 90) (90, "90'") else (end, "$end'"),
            ])
              Positioned(
                left: x(minute) - 20,
                width: 40,
                top: mid + 22,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: label.copyWith(
                    fontSize: 10,
                    color: HeroText.secondary.withValues(alpha: .7),
                  ),
                ),
              ),
            for (final (i, g) in goals.indexed) ...[
              Positioned(
                left: x(g.minute) - 6,
                top: mid - 6,
                width: 12,
                height: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: g.ours
                        ? MilanacColors.goldLight
                        : HeroText.secondary,
                    border: Border.all(color: MilanacColors.black, width: 2),
                    boxShadow: g.ours
                        ? [
                            BoxShadow(
                              color: MilanacColors.gold.withValues(alpha: .6),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Positioned(
                left: x(g.minute) - 20,
                width: 40,
                top: g.ours ? mid - 22 - lift[i] : mid + 10 + lift[i],
                child: Text(
                  "${g.minute}'",
                  textAlign: TextAlign.center,
                  style: label.copyWith(
                    color: g.ours ? HeroText.accent : HeroText.secondary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

/// Riga della cronaca senza gol: calcio d'inizio, intervallo, fischio finale.
class _Moment extends StatelessWidget {
  const _Moment({required this.minute, required this.text, this.trailing});
  final int minute;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            "$minute'",
            style: const TextStyle(
              fontFamily: sportFont,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: HeroText.secondary,
            ),
          ),
        ),
        const Icon(Icons.sports_rounded, size: 18, color: HeroText.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, color: HeroText.secondary),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontFamily: sportFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: HeroText.primary,
            ),
          ),
      ],
    ),
  );
}

/// Un gol nella cronaca: minuto, pallone, "GOL!" con il marcatore (e il suo volto) o
/// il gol subito, e il punteggio dopo il gol.
class _GoalMoment extends StatelessWidget {
  const _GoalMoment({
    required this.goal,
    required this.match,
    required this.member,
    required this.score,
  });
  final MatchGoal goal;
  final ClubMatch match;
  final Member? member;
  final (int, int)? score;

  @override
  Widget build(BuildContext context) {
    final ours = goal.ours;
    final who = ours
        ? member?.displayName ?? goal.scorer ?? match.team.label
        : match.opponent;
    final color = ours ? HeroText.accent : HeroText.secondary;
    final m = member;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              "${goal.minute}'",
              style: TextStyle(
                fontFamily: sportFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Icon(Icons.sports_soccer_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          if (m != null) ...[
            MemberAvatar(
              member: m,
              radius: 15,
              showNumber: false,
              background: CardColors.portrait,
              foreground: HeroText.primary,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ours ? 'GOL!' : 'Gol avversario',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: color,
                  ),
                ),
                Text(
                  who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ours ? HeroText.primary : HeroText.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (score case (final us, final them))
            Text(
              '$us – $them',
              style: const TextStyle(
                fontFamily: sportFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HeroText.primary,
              ),
            ),
        ],
      ),
    );
  }
}
