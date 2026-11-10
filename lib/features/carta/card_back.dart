import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/theme.dart';
import 'card_stats.dart';
import 'fut_card.dart';
import 'fut_card_skin.dart';

/// Le sei statistiche vere (dai dati del club) come le mostra il retro della carta:
/// valore e nome breve.
List<(String, String)> cardNumbers(CardStats stats) {
  String pct(int? v) => v == null ? '–' : '$v%';
  return [
    (pct(stats.presence), 'Presenze'),
    (pct(stats.punctuality), 'Puntualità'),
    ('${stats.nights}', 'Serate'),
    ('${stats.goals}', 'Gol'),
    ('${stats.months}', 'Mesi'),
    (pct(stats.winRate), 'Vittorie'),
  ];
}

/// Il retro della carta: stessa cornice del davanti, e al posto del giocatore i sei
/// numeri veri del club (presenze, puntualità e serate degli ultimi 60 giorni, gol, mesi
/// nel club e vittorie delle sue squadre). Disegnato a 210×300 come il davanti.
class FutCardNumbers extends StatelessWidget {
  const FutCardNumbers({
    super.key,
    required this.skin,
    required this.name,
    required this.stats,
  });
  final CardSkin skin;
  final String name;
  final CardStats stats;

  @override
  Widget build(BuildContext context) {
    final cells = cardNumbers(stats);
    // Valore e nome su una riga ciascuno: se non ci stanno si rimpiccioliscono.
    Widget cell((String, String) c) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                c.$1,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                c.$2.toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: bodyFont,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                  height: 1.3,
                  color: skin.label,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: [
        'Retro della carta di $name',
        for (final (value, label) in cells) '$label $value',
      ].join(', '),
      excludeSemantics: true,
      child: MediaQuery.withNoTextScaling(
        child: AspectRatio(
          aspectRatio: FutCard.width / FutCard.height,
          child: FittedBox(
            child: SizedBox(
              width: FutCard.width,
              height: FutCard.height,
              child: CustomPaint(
                painter: CardGlowPainter(skin.rim),
                child: CardFrame(
                  skin: skin,
                  child: DefaultTextStyle(
                    style: TextStyle(fontFamily: sportFont, color: skin.text),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 22,
                          child: Center(
                            child: Image.asset(
                              'assets/images/stemma_256.png',
                              width: 30,
                              height: 30,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 57,
                          child: Text(
                            'I NUMERI NEL CLUB',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: bodyFont,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              color: skin.label,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 80,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [for (final c in cells.take(3)) cell(c)],
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 130,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [for (final c in cells.skip(3)) cell(c)],
                          ),
                        ),
                        // Sulla targa: il nome, come davanti, e da dove vengono i numeri.
                        Positioned(
                          left: 18,
                          right: 18,
                          top: 196,
                          height: 24,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                name.trim().toUpperCase(),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .4,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 40,
                          right: 40,
                          top: 221,
                          child: Container(
                            height: .8,
                            color: skin.text.withValues(alpha: .35),
                          ),
                        ),
                        Positioned(
                          left: 22,
                          right: 22,
                          top: 228,
                          child: Text(
                            'Presenze, puntualità e serate degli ultimi 60 giorni. '
                            'Gol e vittorie nelle partite delle sue squadre.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: bodyFont,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: skin.label,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La carta che si gira con un tocco: davanti [front], dietro [back]. Con "riduci
/// animazioni" del telefono cambia faccia senza girare.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.onFlip,
  });
  final Widget front;
  final Widget back;

  /// Chiamata a ogni giro: true quando si vede il retro.
  final ValueChanged<bool>? onFlip;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  bool _showBack = false;

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _flip() {
    Haptics.light();
    setState(() => _showBack = !_showBack);
    widget.onFlip?.call(_showBack);
    final target = _showBack ? 1.0 : 0.0;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _turn.value = target;
    } else {
      _turn.animateTo(target, curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    onTapHint: _showBack ? 'tornare al davanti' : 'vedere i numeri nel club',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, _) {
          final angle = _turn.value * math.pi;
          final back = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0011)
              ..rotateY(angle),
            // Il retro si disegna girato, così non si legge allo specchio.
            child: back
                ? Transform.flip(flipX: true, child: widget.back)
                : widget.front,
          );
        },
      ),
    ),
  );
}
