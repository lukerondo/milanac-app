import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../carte/special_cards_repository.dart';
import 'card_stats.dart';

/// La sagoma delle carte, come quelle di FC: angoli in alto intagliati, fianchi dritti e
/// fondo che scende a punta arrotondata. Disegnata nel rettangolo [size].
Path cardOutline(Size size) {
  final w = size.width, h = size.height;
  final r = w * .088; // raggio degli intagli in alto
  return Path()
    ..moveTo(r, 0)
    ..lineTo(w - r, 0)
    ..arcToPoint(Offset(w, r), radius: Radius.circular(r), clockwise: false)
    ..lineTo(w, h * .80)
    ..cubicTo(w, h * .87, w * .80, h * .905, w * .66, h * .935)
    ..cubicTo(w * .58, h * .952, w * .54, h * .975, w * .5, h)
    ..cubicTo(w * .46, h * .975, w * .42, h * .952, w * .34, h * .935)
    ..cubicTo(w * .20, h * .905, 0, h * .87, 0, h * .80)
    ..lineTo(0, r)
    ..arcToPoint(Offset(r, 0), radius: Radius.circular(r), clockwise: false)
    ..close();
}

/// Ritaglia il figlio con la sagoma della carta.
class CardOutlineClipper extends CustomClipper<Path> {
  const CardOutlineClipper();

  @override
  Path getClip(Size size) => cardOutline(size);

  @override
  bool shouldReclip(CardOutlineClipper oldClipper) => false;
}

/// Le decorazioni del fondo.
enum CardPattern {
  /// Sfaccettature di metallo (bronzo, argento, oro, nero/oro).
  facets,

  /// Righe verticali rossonere (85+).
  stripes,

  /// Fulmini d'oro e bagliore azzurro (blu elettrico).
  lightning,
}

/// I colori e le decorazioni di una carta: fondo (tre toni), scritte, linee interne,
/// bordo e, per le carte speciali, il bagliore attorno.
class CardDesign {
  const CardDesign({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.text,
    required this.line,
    required this.edge,
    this.glow,
    this.pattern = CardPattern.facets,
    this.accent,
  });

  final Color top, middle, bottom;
  final Color text;
  final Color line;
  final Color edge;
  final Color? glow;
  final CardPattern pattern;

  /// Il secondo colore delle decorazioni (fulmini, filetti).
  final Color? accent;

  /// La carta speciale vince sul livello dell'overall.
  static CardDesign of(CardSpecial? special, int? overall) => switch (special) {
    CardSpecial.neroOro => neroOro,
    CardSpecial.blu => blu,
    null => switch (tierOf(overall)) {
      CardTier.vuota => vuota,
      CardTier.bronzo => bronzo,
      CardTier.argento => argento,
      CardTier.oro => oro,
      CardTier.rossonera => rossonera,
    },
  };

  static const vuota = CardDesign(
    top: Color(0xFF45454C),
    middle: Color(0xFF26262B),
    bottom: Color(0xFF121214),
    text: Color(0xFFF5F1E6),
    line: Color(0xFF8A8A93),
    edge: Color(0xFF5E5E66),
  );
  static const bronzo = CardDesign(
    top: Color(0xFFF6CB98),
    middle: Color(0xFFC9864A),
    bottom: Color(0xFF7A4A22),
    text: Color(0xFF3B2414),
    line: Color(0xFF7E5128),
    edge: Color(0xFF6E4220),
  );
  static const argento = CardDesign(
    top: Color(0xFFFFFFFF),
    middle: Color(0xFFD0D6DE),
    bottom: Color(0xFF8E97A3),
    text: Color(0xFF20242B),
    line: Color(0xFF6E7681),
    edge: Color(0xFF6B7380),
  );
  static const oro = CardDesign(
    top: Color(0xFFFFF2B8),
    middle: Color(0xFFE8C866),
    bottom: Color(0xFFB88D25),
    text: Color(0xFF3A2A08),
    line: Color(0xFF8F6E1C),
    edge: Color(0xFF8F6E1C),
  );
  static const rossonera = CardDesign(
    top: Color(0xFFE0203E),
    middle: Color(0xFF9A0C22),
    bottom: Color(0xFF1A0507),
    text: Color(0xFFF6D77F),
    line: Color(0xFFE9C964),
    edge: Color(0xFFD6B354),
    pattern: CardPattern.stripes,
  );
  static const neroOro = CardDesign(
    top: Color(0xFF3A3326),
    middle: Color(0xFF15130E),
    bottom: Color(0xFF050505),
    text: Color(0xFFF0D27A),
    line: Color(0xFFC9A227),
    edge: Color(0xFFD6B354),
    glow: Color(0xFFD6B354),
    accent: Color(0xFFE9C964),
  );
  static const blu = CardDesign(
    top: Color(0xFF1C3F99),
    middle: Color(0xFF0B1F5C),
    bottom: Color(0xFF050C29),
    text: Color(0xFFFFFFFF),
    line: Color(0xFF4FE3E8),
    edge: Color(0xFF38E8F0),
    glow: Color(0xFF38E8F0),
    pattern: CardPattern.lightning,
    accent: Color(0xFFF1CF5B),
  );
}

/// Il fondo della carta: sagoma con il metallo sfumato, le decorazioni, la riga interna e
/// il bordo; attorno, per le carte speciali, il bagliore.
class CardFacePainter extends CustomPainter {
  const CardFacePainter(this.design, {this.glow = true});
  final CardDesign design;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = cardOutline(size);
    final d = design;
    final halo = d.glow;
    if (glow && halo != null) {
      canvas.drawPath(
        outline,
        Paint()
          ..color = halo.withValues(alpha: .55)
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, size.width * .05),
      );
    }
    canvas.save();
    canvas.clipPath(outline);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-.6, -1),
          end: const Alignment(.4, 1),
          colors: [d.top, d.middle, d.bottom],
          stops: const [0, .48, 1],
        ).createShader(rect),
    );
    switch (d.pattern) {
      case CardPattern.facets:
        _facets(canvas, size);
      case CardPattern.stripes:
        _stripes(canvas, size);
      case CardPattern.lightning:
        _lightning(canvas, size);
    }
    _sheen(canvas, size);
    canvas.restore();

    // Riga interna e bordo esterno.
    final inset = size.width * .03;
    final inner = cardOutline(
      Size(size.width - inset * 2, size.height - inset * 2),
    ).shift(Offset(inset, inset));
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .007
        ..color = d.line.withValues(alpha: .65),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .012
        ..color = d.edge,
    );
  }

  /// Sfaccettature di metallo: triangoli chiari e scuri che partono dagli angoli.
  void _facets(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final light = Paint()..color = Colors.white.withValues(alpha: .13);
    final dark = Paint()..color = Colors.black.withValues(alpha: .08);
    canvas.drawPath(
      Path()
        ..moveTo(w * .35, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * .30)
        ..close(),
      light,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * .62, 0)
        ..lineTo(w, h * .52)
        ..lineTo(w, h * .30)
        ..close(),
      dark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, h * .55)
        ..lineTo(w * .48, h)
        ..lineTo(0, h)
        ..close(),
      dark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, h * .32)
        ..lineTo(w * .30, h * .62)
        ..lineTo(0, h * .70)
        ..close(),
      light,
    );
    final accent = design.accent;
    if (accent != null) {
      // Nero/oro: filetti d'oro come le carte della settimana.
      final gold = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .006
        ..color = accent.withValues(alpha: .55);
      canvas
        ..drawLine(Offset(w * .55, 0), Offset(w, h * .42), gold)
        ..drawLine(Offset(w * .70, 0), Offset(w, h * .26), gold)
        ..drawLine(Offset(0, h * .62), Offset(w * .36, h), gold);
    }
  }

  /// Righe verticali rossonere, come la maglia.
  void _stripes(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final black = Paint()..color = Colors.black.withValues(alpha: .42);
    final band = w / 7;
    for (var i = 0; i < 7; i += 2) {
      canvas.drawRect(Rect.fromLTWH(band * i + band * .5, 0, band, h), black);
    }
  }

  /// Fulmini d'oro in alto a destra e lampi azzurri, come le carte della stagione.
  void _lightning(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final teal = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF38E8F0).withValues(alpha: .45),
              const Color(0xFF38E8F0).withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(center: Offset(w * .1, h * .12), radius: w * .55),
          );
    canvas.drawRect(Offset.zero & size, teal);
    // Scie diagonali azzurre.
    final streak = Paint()
      ..strokeWidth = w * .012
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4FE3E8).withValues(alpha: .35);
    for (var i = 0; i < 6; i++) {
      final x = w * (.04 + i * .07);
      canvas.drawLine(Offset(x, h * .02), Offset(x + w * .10, h * .20), streak);
    }
    final accent = design.accent ?? const Color(0xFFF1CF5B);
    final bolt = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .022
      ..strokeJoin = StrokeJoin.miter
      ..color = accent;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .05
      ..color = accent.withValues(alpha: .35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .02);
    for (final (x, y, s) in [(.74, .06, 1.0), (.86, .14, .7)]) {
      final path = Path()
        ..moveTo(w * x, h * y)
        ..lineTo(w * (x - .05 * s), h * (y + .09 * s))
        ..lineTo(w * (x + .01 * s), h * (y + .09 * s))
        ..lineTo(w * (x - .06 * s), h * (y + .20 * s));
      canvas
        ..drawPath(path, glow)
        ..drawPath(path, bolt);
    }
  }

  /// La luce che attraversa la carta in diagonale.
  void _sheen(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -1),
          end: const Alignment(1, 1),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .16),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [.30, .42, .54],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CardFacePainter oldDelegate) =>
      oldDelegate.design != design || oldDelegate.glow != glow;
}

/// Una piccola riga orizzontale (sotto ruolo e bandiera, sotto il nome).
class CardRule extends StatelessWidget {
  const CardRule({super.key, required this.color, this.width = 30});
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) =>
      Container(width: width, height: 1.4, color: color.withValues(alpha: .7));
}

/// Angolo in radianti (per le decorazioni ruotate).
double degrees(double d) => d * math.pi / 180;
