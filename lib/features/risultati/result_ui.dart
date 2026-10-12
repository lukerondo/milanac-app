import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import 'match.dart';

/// Pezzi comuni delle schermate di partite, tornei e carte (stile nero oro).

String outcomeLabel(MatchOutcome o) => switch (o) {
  MatchOutcome.vittoria => 'Vittoria',
  MatchOutcome.pareggio => 'Pareggio',
  MatchOutcome.sconfitta => 'Sconfitta',
  MatchOutcome.daGiocare => 'Da giocare',
};

/// Colore del testo e del fondo di un esito, dalla tavolozza [p].
(Color, Color) outcomeColors(AppPalette p, MatchOutcome o) => switch (o) {
  MatchOutcome.vittoria => (p.success, p.successBg),
  MatchOutcome.pareggio => (p.textSecondary, p.border),
  MatchOutcome.sconfitta => (p.danger, p.dangerBg),
  MatchOutcome.daGiocare => (p.accentText, p.accentTint),
};

/// Il punteggio dalla parte del club: "3 – 1" (i nostri gol prima), "–" se da giocare.
String scoreText(ClubMatch m) => m.outcome == MatchOutcome.daGiocare
    ? '–'
    : '${m.goalsFor} – ${m.goalsAgainst}';

/// Nome breve della squadra nei filtri a pillola ("Milan AC", "Futuro").
String teamPillLabel(Team t) => switch (t) {
  Team.milanac => 'Milan AC',
  Team.futuro => 'Futuro',
};

/// "FVPA Serie B – 2ª giornata", "Amichevole · Futuro · in trasferta".
String matchSubtitle(ClubMatch m) => [
  m.competition ?? m.kind.label,
  if (m.team == Team.futuro) 'Futuro',
  if (!m.home) 'in trasferta',
].join(' · ');

/// "oggi", "ieri", "5 giorni fa", "domani", "tra 3 giorni" oppure la data, per un giorno
/// rispetto a [now] (in ora italiana, come il resto dell'app).
String relativeDay(DateTime when, DateTime now) {
  final day = italianDay(when);
  final today = italianDay(now);
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  return switch (days) {
    0 => 'oggi',
    1 => 'ieri',
    -1 => 'domani',
    > 1 && < 14 => '$days giorni fa',
    < -1 && > -14 => 'tra ${-days} giorni',
    _ =>
      day.year == today.year
          ? DateFormat('d MMMM', 'it').format(day)
          : DateFormat('d MMMM yyyy', 'it').format(day),
  };
}

/// Riquadro V / N / P dell'esito (con la parola per chi usa il lettore di schermo).
class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge(this.outcome, {super.key, this.size = 32});
  final MatchOutcome outcome;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = outcomeColors(context.pal, outcome);
    final letter = switch (outcome) {
      MatchOutcome.vittoria => 'V',
      MatchOutcome.pareggio => 'N',
      MatchOutcome.sconfitta => 'P',
      MatchOutcome.daGiocare => '–',
    };
    return Semantics(
      label: outcomeLabel(outcome),
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontFamily: sportFont,
            fontWeight: FontWeight.w600,
            fontSize: size * .5,
            height: 1,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// Pillola di stato ("In corso", "Vittoria · 5 giorni fa").
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.text, {
    super.key,
    required this.color,
    required this.background,
    this.fontSize = 13,
  });
  final String text;
  final Color color;
  final Color background;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: fontSize < 14 ? 10 : 12,
      vertical: 4,
    ),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// Filo d'oro che sfuma ai lati, sotto le intestazioni scure (risultato, carta).
class GoldFadeLine extends StatelessWidget {
  const GoldFadeLine({super.key, this.color = MilanacColors.goldLight});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    width: double.infinity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

/// Lo stemma del club con gli angoli arrotondati (l'immagine ha il fondo nero).
class ClubCrest extends StatelessWidget {
  const ClubCrest({super.key, this.size = 60});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .18),
    child: Image.asset(
      'assets/images/stemma_256.png',
      width: size,
      height: size,
    ),
  );
}

/// Iniziali di un nome per i tondi senza foto ("Dinamo Pixel" → "DP").
String initialsOf(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.single;
    return w.characters.take(2).toString().toUpperCase();
  }
  return (words[0].characters.first + words[1].characters.first).toUpperCase();
}

/// Nome breve sotto le foto piccole: il cognome ("Marco Rossi" → "Rossi").
String shortName(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  return words.isEmpty || words.last.isEmpty ? name : words.last;
}
