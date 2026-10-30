import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../carte/special_cards_repository.dart';
import 'card_colors.dart';
import 'fut_card_skin.dart';

/// La carta "viva" come in FC: ogni pochi secondi un riflesso le passa sopra, toccandola
/// si inclina seguendo il dito (e torna dritta lasciandola, con un riflesso che segue la
/// luce) e le carte speciali brillano. Con "riduci animazioni" del telefono il riflesso
/// non parte da solo; l'inclinazione resta, perché la guida il dito.
///
/// [child] è la carta (anche dentro margini: [padding] è lo spazio tra il bordo del
/// widget e la carta); riflessi e brillii stanno sopra, fuori dal [child], così
/// l'immagine condivisa della carta resta pulita.
class LiveCard extends StatefulWidget {
  const LiveCard({
    super.key,
    required this.child,
    this.special,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final CardSpecial? special;
  final EdgeInsets padding;

  /// Un riflesso ogni tanto: abbastanza per vederla viva, non tanto da distrarre.
  static const sweepEvery = Duration(seconds: 5);
  static const sweepDuration = Duration(milliseconds: 1400);

  @override
  State<LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<LiveCard> with TickerProviderStateMixin {
  /// Inclinazione massima (circa 12 gradi).
  static const _maxTilt = .21;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: LiveCard.sweepDuration,
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Timer? _next;

  /// Dove punta il dito: da -1 a 1 su ciascun asse (0, 0 = carta dritta).
  Offset _tilt = Offset.zero;
  Offset _releasedAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final t = Curves.easeOutBack.transform(_settle.value);
      setState(() => _tilt = Offset.lerp(_releasedAt, Offset.zero, t)!);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _shine());
  }

  void _shine() {
    if (!mounted) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!still) _sweep.forward(from: 0);
    _next = Timer(LiveCard.sweepEvery, _shine);
  }

  @override
  void dispose() {
    _next?.cancel();
    _sweep.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _follow(Offset local, Size size) {
    if (size.isEmpty) return;
    _settle.stop();
    setState(() {
      _tilt = Offset(
        (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  void _letGo() {
    if (_tilt == Offset.zero) return;
    _releasedAt = _tilt;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..rotateX(-_tilt.dy * _maxTilt)
      ..rotateY(_tilt.dx * _maxTilt);
    return Listener(
      // Ascolto del dito senza prendere il gesto: la pagina sotto continua a
      // scorrere anche partendo dalla carta. Tutta l'area della carta risponde.
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _follow(e.localPosition, context.size ?? Size.zero),
      onPointerMove: (e) => _follow(e.localPosition, context.size ?? Size.zero),
      onPointerUp: (_) => _letGo(),
      onPointerCancel: (_) => _letGo(),
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: widget.padding,
                  // I riflessi restano dentro la forma della carta FUT.
                  child: ClipPath(
                    clipper: const FutCardClipper(),
                    child: AnimatedBuilder(
                      animation: _sweep,
                      builder: (context, _) => CustomPaint(
                        painter: CardShinePainter(
                          sweep: _sweep.isAnimating ? _sweep.value : null,
                          tilt: _tilt,
                          special: widget.special,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Riflessi della carta: la striscia di luce che passa ([sweep] da 0 a 1, null se
/// ferma), il riflesso che segue l'inclinazione e i brillii delle carte speciali.
class CardShinePainter extends CustomPainter {
  const CardShinePainter({
    required this.sweep,
    required this.tilt,
    this.special,
  });
  final double? sweep;
  final Offset tilt;
  final CardSpecial? special;

  /// Punti dei brillii (in frazioni della carta) e il momento del passaggio in cui
  /// ciascuno si accende: sul bordo e vicino a overall e stemma, come le carte FUT.
  static const _sparks = [
    (Offset(.12, .07), .05),
    (Offset(.88, .1), .2),
    (Offset(.94, .45), .35),
    (Offset(.06, .52), .45),
    (Offset(.85, .86), .6),
    (Offset(.2, .93), .7),
    (Offset(.5, .03), .82),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final s = sweep;
    if (s != null) {
      // Striscia diagonale che attraversa la carta; si sposta un po' con la luce.
      final t = Curves.easeInOut.transform(s);
      final center = -.6 + 2.2 * t + tilt.dx * .15;
      final band = LinearGradient(
        begin: Alignment(center - .5, -1),
        end: Alignment(center + .5, 1),
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: .05),
          const Color(0xFFFFF1C8).withValues(alpha: .32),
          Colors.white.withValues(alpha: .05),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, .38, .5, .62, 1],
      );
      canvas.drawRect(rect, Paint()..shader = band.createShader(rect));
    }
    if (tilt != Offset.zero) {
      // Riflesso morbido dove "batte la luce", opposto al dito.
      final glare = RadialGradient(
        center: Alignment(-tilt.dx * .8, -tilt.dy * .8),
        radius: .9,
        colors: [
          Colors.white.withValues(alpha: .16 * tilt.distance.clamp(0, 1)),
          Colors.white.withValues(alpha: 0),
        ],
      );
      canvas.drawRect(rect, Paint()..shader = glare.createShader(rect));
    }
    final kind = special;
    if (kind != null && s != null) {
      // Sul blu brillii bianco-azzurri (l'azzurro sparirebbe), sul nero/oro d'oro chiaro.
      final color = kind == CardSpecial.blu
          ? CardColors.onBlueMuted
          : CardColors.metalLight;
      for (final (at, phase) in _sparks) {
        // Ogni brillio si accende e si spegne durante il passaggio, a turno.
        final life = ((s - phase) / .3).clamp(0.0, 1.0);
        if (life <= 0 || life >= 1) continue;
        _star(
          canvas,
          Offset(at.dx * size.width, at.dy * size.height),
          size.shortestSide * .045 * math.sin(math.pi * life),
          color.withValues(alpha: math.sin(math.pi * life)),
        );
      }
    }
  }

  /// Stella a quattro punte (il brillio delle carte speciali).
  void _star(Canvas canvas, Offset c, double r, Color color) {
    if (r <= 0) return;
    final w = r * .22;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(
      c,
      r * .5,
      Paint()
        ..color = color.withValues(alpha: color.a * .35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .6),
    );
  }

  @override
  bool shouldRepaint(CardShinePainter old) =>
      old.sweep != sweep || old.tilt != tilt || old.special != special;
}
