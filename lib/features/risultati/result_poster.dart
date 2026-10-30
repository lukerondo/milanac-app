import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/theme.dart';
import '../../shared/gold_loader.dart';
import '../../shared/ui.dart';
import '../carta/card_colors.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../walkout/walkout_fx.dart';
import 'match.dart';
import 'match_tv.dart';
import 'result_ui.dart';

/// La grafica del risultato da condividere (WhatsApp, Instagram...): come i poster dei
/// club a fine partita, nero oro con San Siro di notte, il punteggio nelle caselle del
/// tabellone, i marcatori con i minuti e le carte della giornata.

/// Il testo del risultato (per chi preferisce condividerlo scritto).
String resultShareText(ClubMatch match, Iterable<Member> roster) {
  final played = match.outcome != MatchOutcome.daGiocare;
  final scorers = played
      ? scorerTicker(match, matchPlayers(roster, match))
      : const <String>[];
  final against = [
    for (final g in match.timeline)
      if (!g.ours) "${g.minute}'",
  ];
  return [
    played
        ? '${match.team.label} ${scoreText(match)} ${match.opponent}'
        : '${match.team.label} – ${match.opponent}',
    matchSubtitle(match),
    if (scorers.isNotEmpty) 'Marcatori: ${scorers.join(', ')}',
    if (played && against.isNotEmpty)
      'Gol ${match.opponent}: ${against.join(' ')}',
    'MILANAC Pro Club',
  ].join('\n');
}

/// Apre la pagina con l'anteprima della grafica e i pulsanti per condividerla.
Future<void> openResultPoster(BuildContext context, ClubMatch match) =>
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => ResultPosterPage(match: match)));

class ResultPosterPage extends ConsumerStatefulWidget {
  const ResultPosterPage({super.key, required this.match});
  final ClubMatch match;

  @override
  ConsumerState<ResultPosterPage> createState() => _ResultPosterPageState();
}

class _ResultPosterPageState extends ConsumerState<ResultPosterPage> {
  final _posterKey = GlobalKey();
  bool _sharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lo stemma deve essere già caricato quando si fa l'immagine.
    precacheImage(const AssetImage('assets/images/stemma_256.png'), context);
  }

  /// L'immagine (1080×1350, 4:5: sta intera su Instagram e WhatsApp).
  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _posterKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final m = widget.match;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png'),
          ],
          fileNameOverrides: ['risultato_${m.id}.png'],
          text:
              '${m.team.label} ${scoreText(m)} ${m.opponent} · MILANAC Pro Club',
        ),
      );
      Haptics.confirm();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Condivisione non riuscita')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareText() async {
    final roster = ref.read(rosaProvider).value ?? const <Member>[];
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(text: resultShareText(widget.match, roster)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Condivisione non riuscita')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.hero,
        title: const Text('CONDIVIDI IL RISULTATO'),
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  // L'anteprima si adatta allo schermo; l'immagine condivisa è quella
                  // disegnata a 360×450 e resa a tre volte.
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _posterKey,
                      child: ResultPoster(match: widget.match),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _sharing ? null : _shareImage,
                    icon: _sharing
                        ? GoldLoader(size: 18, color: p.onAccent)
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(
                      _sharing
                          ? 'Preparo l\'immagine…'
                          : 'Condividi l\'immagine',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _shareText,
                    child: const Text('Condividi come testo'),
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

/// Il poster: 360×450 (4:5), sempre scuro come gli oggetti di gioco.
class ResultPoster extends ConsumerWidget {
  const ResultPoster({super.key, required this.match});
  final ClubMatch match;

  static const width = 360.0, height = 450.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const dark = AppPalette.dark;
    final roster = ref.watch(rosaProvider).value ?? const <Member>[];
    final members = {for (final m in roster) m.id: m};
    final players = matchPlayers(roster, match);
    final played = match.outcome != MatchOutcome.daGiocare;
    final (fg, bg) = outcomeColors(dark, match.outcome);
    final scorers = played ? scorerTicker(match, players) : const <String>[];
    final against = [
      for (final g in match.timeline)
        if (!g.ours) "${g.minute}'",
    ];
    final cards =
        (ref.watch(specialCardsProvider).value ?? const <SpecialCard>[])
            .where((c) => c.matchId == match.id)
            .toList()
          ..sort(compareCardsForDisplay);
    final date = DateFormat('d MMMM yyyy', 'it').format(match.playedAt);
    final accent = switch (match.outcome) {
      MatchOutcome.vittoria => MilanacColors.goldLight,
      MatchOutcome.pareggio => MilanacColors.ivory,
      MatchOutcome.sconfitta => MilanacColors.ivoryMuted,
      MatchOutcome.daGiocare => MilanacColors.goldLight,
    };
    const small = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: HeroText.secondary,
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: MilanacColors.black),
            // San Siro di notte con i riflettori accesi, come nel walkout.
            CustomPaint(
              painter: WalkoutBackdropPainter(
                color: MilanacColors.gold,
                glow: .7,
                beams: .45,
                spin: .6,
                twinkle: 3,
                lights: 1,
              ),
            ),
            // Buio sulla tribuna: le scritte in basso restano leggibili.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(0, .3),
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xD90B0B0C)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: Column(
                children: [
                  const Text(
                    'MILANAC PRO CLUB',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                      color: HeroText.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      competitionLabel(match),
                      if (!match.home) 'in trasferta',
                      date,
                    ].join(' · ').toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: small,
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Side(
                          name: match.team.label,
                          badge: const ClubCrest(size: 64),
                          lines: scorers,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _Score(match: match, color: accent),
                      ),
                      Expanded(
                        child: _Side(
                          name: match.opponent,
                          badge: Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CardColors.portrait,
                            ),
                            child: Text(
                              initialsOf(match.opponent),
                              style: const TextStyle(
                                fontFamily: sportFont,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: HeroText.secondary,
                              ),
                            ),
                          ),
                          lines: against.isEmpty
                              ? const []
                              : [against.join(' ')],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (played)
                    StatusPill(
                      outcomeLabel(match.outcome).toUpperCase(),
                      color: fg,
                      background: bg,
                      fontSize: 13,
                    ),
                  const Spacer(),
                  // Carte e nota: se sono tante si rimpiccioliscono, l'immagine resta 4:5.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: width - 44,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cards.isNotEmpty) ...[
                              const Text('CARTE DELLA GIORNATA', style: small),
                              const SizedBox(height: 6),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  for (final c in cards)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          c.isBlue
                                              ? Icons.bolt_rounded
                                              : Icons.star_rounded,
                                          size: 15,
                                          color: c.isBlue
                                              ? CardColors.blueRing
                                              : HeroText.accent,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${members[c.playerId]?.displayName.split(' ').last ?? 'Ex membro'} '
                                          '${c.reparto} +${c.bonus}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: c.isBlue
                                                ? CardColors.blueText
                                                : HeroText.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (match.notes?.trim().isNotEmpty ?? false) ...[
                              Text(
                                '«${match.notes!.trim()}»',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: HeroText.secondary,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    'MILANO SIAMO NOI',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: HeroText.accent,
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

/// Stemma, nome e marcatori di una squadra nel poster.
class _Side extends StatelessWidget {
  const _Side({required this.name, required this.badge, required this.lines});
  final String name;
  final Widget badge;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      badge,
      const SizedBox(height: 8),
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
      // Al massimo quattro righe di marcatori: oltre, puntini.
      for (final (i, l) in lines.take(4).indexed)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            i == 3 && lines.length > 4 ? '$l …' : l,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: HeroText.secondary),
          ),
        ),
    ],
  );
}

/// Il punteggio nelle caselle del tabellone (o "VS" se da giocare).
class _Score extends StatelessWidget {
  const _Score({required this.match, required this.color});
  final ClubMatch match;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final played = match.outcome != MatchOutcome.daGiocare;
    Widget box(String text) => Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
        style: TextStyle(
          fontFamily: sportFont,
          fontSize: 40,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: color,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: played
            ? [
                box('${match.goalsFor}'),
                const SizedBox(width: 4),
                box('${match.goalsAgainst}'),
              ]
            : [box('VS')],
      ),
    );
  }
}
