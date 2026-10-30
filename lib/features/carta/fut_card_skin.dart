import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../carte/special_cards_repository.dart';
import 'card_stats.dart';

/// Il profilo della carta FUT (come in FC 24–26) dentro [r]: scudo alto con i lati
/// dritti, tacche concave negli angoli in alto, angoli bassi arrotondati e una punta
/// appena accennata al centro in basso.
Path futCardPathIn(Rect r) {
  final w = r.width, h = r.height;
  Offset at(double x, double y) => Offset(r.left + w * x, r.top + h * y);
  final a = at(.16, 0), b = at(.84, 0);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..quadraticBezierTo(
      at(.85, .09).dx,
      at(.85, .09).dy,
      at(1, .1).dx,
      at(1, .1).dy,
    )
    ..lineTo(at(1, .89).dx, at(1, .89).dy)
    ..quadraticBezierTo(
      at(1, .94).dx,
      at(1, .94).dy,
      at(.9, .955).dx,
      at(.9, .955).dy,
    )
    ..lineTo(at(.56, .99).dx, at(.56, .99).dy)
    ..quadraticBezierTo(
      at(.5, 1).dx,
      at(.5, 1).dy,
      at(.44, .99).dx,
      at(.44, .99).dy,
    )
    ..lineTo(at(.1, .955).dx, at(.1, .955).dy)
    ..quadraticBezierTo(
      at(0, .94).dx,
      at(0, .94).dy,
      at(0, .89).dx,
      at(0, .89).dy,
    )
    ..lineTo(at(0, .1).dx, at(0, .1).dy)
    ..quadraticBezierTo(at(.15, .09).dx, at(.15, .09).dy, a.dx, a.dy)
    ..close();
}

Path futCardPath(Size size) => futCardPathIn(Offset.zero & size);

/// Ritaglia sulla forma della carta (riflessi della carta viva, foto, voli).
class FutCardClipper extends CustomClipper<Path> {
  const FutCardClipper();

  @override
  Path getClip(Size size) => futCardPath(size);

  @override
  bool shouldReclip(FutCardClipper oldClipper) => false;
}

enum CardOrnament { none, rays, facets, shards, stripes }

/// Il "materiale" di una carta: sfumatura metallica, scritte, bordi e decorazioni. Colori
/// fissi: è un oggetto di gioco, uguale nei due temi.
@immutable
class CardSkin {
  const CardSkin({
    required this.gradient,
    required this.text,
    required this.label,
    required this.rim,
    required this.inner,
    required this.ornamentColor,
    required this.ornament,
  });

  final List<Color> gradient;

  /// Overall, ruolo, nome e valori; [label] per le sigle delle statistiche.
  final Color text;
  final Color label;

  /// Bordo esterno e filetto interno.
  final Color rim;
  final Color inner;
  final Color ornamentColor;
  final CardOrnament ornament;

  /// Bronzo, argento e oro sono le carte rare di FUT (soglie 65 e 75); sopra 85 la carta
  /// rossonera del club; senza overall una carta grigia.
  static CardSkin of(CardSpecial? special, int? overall) => switch (special) {
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

  static const vuota = CardSkin(
    gradient: [Color(0xFF6A6A72), Color(0xFF43434A), Color(0xFF2C2C31)],
    text: Color(0xFFF5F1E6),
    label: Color(0xFFCFCAC0),
    rim: Color(0xFF7C7C84),
    inner: Color(0xFF9A9AA2),
    ornamentColor: Color(0xFFFFFFFF),
    ornament: CardOrnament.none,
  );
  static const bronzo = CardSkin(
    gradient: [
      Color(0xFFF3CDA4),
      Color(0xFFD49A62),
      Color(0xFFA86A3B),
      Color(0xFFC98A55),
      Color(0xFF7E4B25),
    ],
    text: Color(0xFF2E1B0C),
    label: Color(0xFF4A2E17),
    rim: Color(0xFF6E4020),
    inner: Color(0xFFF6D6B2),
    ornamentColor: Color(0xFFFFFFFF),
    ornament: CardOrnament.rays,
  );
  static const argento = CardSkin(
    gradient: [
      Color(0xFFFFFFFF),
      Color(0xFFDDE2E6),
      Color(0xFFA9B2B9),
      Color(0xFFD5DADF),
      Color(0xFF8F99A1),
    ],
    text: Color(0xFF1F2427),
    label: Color(0xFF3A4247),
    rim: Color(0xFF7D868D),
    inner: Color(0xFFFFFFFF),
    ornamentColor: Color(0xFFFFFFFF),
    ornament: CardOrnament.rays,
  );
  static const oro = CardSkin(
    gradient: [
      Color(0xFFFCEFB4),
      Color(0xFFE8C766),
      Color(0xFFC9A13A),
      Color(0xFFE3C26A),
      Color(0xFFA8822E),
    ],
    text: Color(0xFF3A2C0B),
    label: Color(0xFF5A4614),
    rim: Color(0xFF8E6B1E),
    inner: Color(0xFFFFF4C8),
    ornamentColor: Color(0xFFFFFFFF),
    ornament: CardOrnament.rays,
  );
  static const rossonera = CardSkin(
    gradient: [
      Color(0xFFD6182F),
      Color(0xFF8E0B1E),
      Color(0xFF1A0508),
      Color(0xFF0B0B0C),
    ],
    text: Color(0xFFF6D77F),
    label: Color(0xFFE9C964),
    rim: Color(0xFFD9B65A),
    inner: Color(0xFF8C6F2A),
    ornamentColor: Color(0xFF000000),
    ornament: CardOrnament.stripes,
  );
  static const neroOro = CardSkin(
    gradient: [Color(0xFF26231C), Color(0xFF111112), Color(0xFF050505)],
    text: Color(0xFFEBCB73),
    label: Color(0xFFC9AE68),
    rim: Color(0xFFD9B65A),
    inner: Color(0xFF8C6F2A),
    ornamentColor: Color(0xFFC9A646),
    ornament: CardOrnament.facets,
  );
  static const blu = CardSkin(
    gradient: [
      Color(0xFF1F5BFF),
      Color(0xFF0B2E8A),
      Color(0xFF06123A),
      Color(0xFF0A1A55),
    ],
    text: Color(0xFFFFFFFF),
    label: Color(0xFFD6E2FF),
    rim: Color(0xFFE7C76B),
    inner: Color(0xFF5CC8FF),
    ornamentColor: Color(0xFF5CC8FF),
    ornament: CardOrnament.shards,
  );
}

/// Fondo della carta: sfumatura metallica, decorazioni, riflesso fisso, bordo esterno e
/// filetto interno, tutto sulla forma FUT.
class CardSkinPainter extends CustomPainter {
  const CardSkinPainter(this.skin, {this.rimWidth = 2});
  final CardSkin skin;
  final double rimWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = futCardPath(size);
    canvas.save();
    canvas.clipPath(shape);
    final colors = skin.gradient;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: [
            for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
          ],
        ).createShader(rect),
    );
    switch (skin.ornament) {
      case CardOrnament.none:
        break;
      case CardOrnament.rays:
        _rays(canvas, size);
      case CardOrnament.facets:
        _facets(canvas, size, .3);
      case CardOrnament.shards:
        _facets(canvas, size, .22);
      case CardOrnament.stripes:
        _stripes(canvas, size);
    }
    // Riflesso fisso in diagonale, come il lucido delle carte rare.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -.6),
          end: const Alignment(1, .6),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .22),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [.32, .42, .52],
        ).createShader(rect),
    );
    canvas.restore();
    // Filetto interno e bordo.
    final inset = size.width * .035;
    canvas.drawPath(
      futCardPathIn(rect.deflate(inset)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .006
        ..color = skin.inner.withValues(alpha: .85),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..color = skin.rim,
    );
  }

  /// Raggi di luce che partono da dietro il ritratto (carte rare).
  void _rays(Canvas canvas, Size size) {
    final c = Offset(size.width * .6, size.height * .3);
    final r = size.longestSide * 1.2;
    final paint = Paint()..color = skin.ornamentColor.withValues(alpha: .1);
    const n = 20;
    for (var i = 0; i < n; i += 2) {
      final a0 = i * 2 * math.pi / n, a1 = (i + 1) * 2 * math.pi / n;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
          ..lineTo(c.dx + r * math.cos(a1), c.dy + r * math.sin(a1))
          ..close(),
        paint,
      );
    }
  }

  /// Sfaccettature geometriche (nero/oro, blu elettrico): triangoli e linee sottili.
  void _facets(Canvas canvas, Size size, double alpha) {
    final w = size.width, h = size.height;
    final fill = Paint()
      ..color = skin.ornamentColor.withValues(alpha: alpha * .35);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .005
      ..color = skin.ornamentColor.withValues(alpha: alpha);
    const tris = [
      [0.0, .18, .34, .02, .22, .36],
      [.62, 0.0, 1.0, .08, .9, .34],
      [0.0, .62, .2, .48, .12, .8],
      [.78, .55, 1.0, .46, 1.0, .74],
      [.3, .78, .56, .7, .48, .95],
    ];
    for (final t in tris) {
      final p = Path()
        ..moveTo(w * t[0], h * t[1])
        ..lineTo(w * t[2], h * t[3])
        ..lineTo(w * t[4], h * t[5])
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, line);
    }
    for (final y in const [.66, .69]) {
      canvas.drawLine(Offset(w * .08, h * y), Offset(w * .92, h * y), line);
    }
  }

  /// Righe rossonere strette (carta rossonera del club).
  void _stripes(Canvas canvas, Size size) {
    final w = size.width;
    final stripe = w / 15;
    final paint = Paint()..color = const Color(0x55000000);
    for (var x = stripe; x < w; x += stripe * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(CardSkinPainter old) =>
      old.skin != skin || old.rimWidth != rimWidth;
}
