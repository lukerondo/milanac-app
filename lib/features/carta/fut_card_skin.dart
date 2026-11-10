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

/// Il "materiale" di una carta: la cornice disegnata (metallo spazzolato, archi in
/// rilievo, targa bassa: immagini in assets/carte/, generate da tools/carte), i colori
/// delle scritte e dei bordi. Colori fissi: è un oggetto di gioco, uguale nei due temi.
@immutable
class CardSkin {
  const CardSkin({
    required this.asset,
    required this.gradient,
    required this.text,
    required this.label,
    required this.rim,
    required this.inner,
  });

  /// Nome delle immagini della cornice: `assets/carte/<asset>_fondo.webp` e `_targa.webp`.
  final String asset;

  /// La sfumatura del materiale: fondo di riserva finché la cornice non è pronta.
  final List<Color> gradient;

  /// Overall, ruolo, nome e valori; [label] per le sigle delle statistiche.
  final Color text;
  final Color label;

  /// Bordo esterno e filetto interno.
  final Color rim;
  final Color inner;

  String get background => 'assets/carte/${asset}_fondo.webp';
  String get plate => 'assets/carte/${asset}_targa.webp';

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

  static const all = [vuota, bronzo, argento, oro, rossonera, neroOro, blu];

  static const vuota = CardSkin(
    asset: 'vuota',
    gradient: [
      Color(0xFF8A8A93),
      Color(0xFF5F5F68),
      Color(0xFF3E3E45),
      Color(0xFF55555D),
      Color(0xFF27272C),
    ],
    text: Color(0xFFF5F1E6),
    label: Color(0xFFCFCAC0),
    rim: Color(0xFF7C7C84),
    inner: Color(0xFFB4B4BC),
  );
  static const bronzo = CardSkin(
    asset: 'bronzo',
    gradient: [
      Color(0xFFF6D3AE),
      Color(0xFFD29660),
      Color(0xFF9A5E33),
      Color(0xFFC4854F),
      Color(0xFF70421F),
    ],
    text: Color(0xFF2B1808),
    label: Color(0xFF4A2C14),
    rim: Color(0xFF6B3E1D),
    inner: Color(0xFFFBE2C6),
  );
  static const argento = CardSkin(
    asset: 'argento',
    gradient: [
      Color(0xFFFFFFFF),
      Color(0xFFD9DFE4),
      Color(0xFF9FA9B1),
      Color(0xFFCDD4D9),
      Color(0xFF7C8790),
    ],
    text: Color(0xFF1B2024),
    label: Color(0xFF353D43),
    rim: Color(0xFF6F7981),
    inner: Color(0xFFFFFFFF),
  );
  static const oro = CardSkin(
    asset: 'oro',
    gradient: [
      Color(0xFFFFF3BF),
      Color(0xFFEBCB6C),
      Color(0xFFC19A33),
      Color(0xFFE2C063),
      Color(0xFF9B7724),
    ],
    text: Color(0xFF33260A),
    label: Color(0xFF544011),
    rim: Color(0xFF876419),
    inner: Color(0xFFFFF6CF),
  );
  static const rossonera = CardSkin(
    asset: 'rossonera',
    gradient: [
      Color(0xFFE01E36),
      Color(0xFFA00F22),
      Color(0xFF4A0810),
      Color(0xFF16090B),
      Color(0xFF0B0B0C),
    ],
    text: Color(0xFFF6D77F),
    label: Color(0xFFE3C469),
    rim: Color(0xFFD9B65A),
    inner: Color(0xFF8C6F2A),
  );
  static const neroOro = CardSkin(
    asset: 'nero_oro',
    gradient: [
      Color(0xFF34302A),
      Color(0xFF19181A),
      Color(0xFF0A0A0B),
      Color(0xFF151416),
      Color(0xFF050505),
    ],
    text: Color(0xFFEBCB73),
    label: Color(0xFFC9AE68),
    rim: Color(0xFFD9B65A),
    inner: Color(0xFF8C6F2A),
  );
  static const blu = CardSkin(
    asset: 'blu',
    gradient: [
      Color(0xFF3B74FF),
      Color(0xFF1747C8),
      Color(0xFF0A2A80),
      Color(0xFF0C2F92),
      Color(0xFF050F33),
    ],
    text: Color(0xFFFFFFFF),
    label: Color(0xFFD3E0FF),
    rim: Color(0xFFE7C76B),
    inner: Color(0xFF6FCBFF),
  );
}

/// Fondo di riserva della carta: la sfumatura del materiale sulla forma FUT. Si vede
/// finché l'immagine della cornice non è pronta (primo istante, test).
class CardSkinPainter extends CustomPainter {
  const CardSkinPainter(this.skin);
  final CardSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = skin.gradient;
    canvas.drawPath(
      futCardPath(size),
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
  }

  @override
  bool shouldRepaint(CardSkinPainter old) => old.skin != skin;
}

/// I bordi della carta, sopra a tutto (la foto non esce mai): filetto interno con la
/// sua ombra, bordo e un filo di luce. Misure pensate per la carta larga 210.
class CardRimPainter extends CustomPainter {
  const CardRimPainter(this.skin, {this.rimWidth = 2.4});
  final CardSkin skin;
  final double rimWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final u = size.width / 210;
    void line(double inset, Color color, double width) => canvas.drawPath(
      futCardPathIn(rect.deflate(inset * u)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
    line(6.3, skin.inner.withValues(alpha: .9), .9 * u);
    line(7.85, Colors.black.withValues(alpha: .22), .7 * u);
    line(0, skin.rim, rimWidth);
    line(1.1, Colors.white.withValues(alpha: .45), .63 * u);
  }

  @override
  bool shouldRepaint(CardRimPainter old) =>
      old.skin != skin || old.rimWidth != rimWidth;
}

/// La carta come oggetto: la cornice del materiale, il giocatore dietro la targa bassa
/// (che lo taglia, come nelle carte da collezione), le scritte e i bordi.
class CardFrame extends StatelessWidget {
  const CardFrame({
    super.key,
    required this.skin,
    required this.child,
    this.figure,
    this.rimWidth = 2.4,
    this.decodeWidth,
  });
  final CardSkin skin;

  /// Il giocatore (foto o omino), già al suo posto: sta sopra il fondo e sotto la targa.
  final Widget? figure;

  /// Scritte, numeri e stemma.
  final Widget child;
  final double rimWidth;

  /// Larghezza in pixel a cui decodificare la cornice (carte piccole).
  final int? decodeWidth;

  /// Dove comincia l'immagine della targa (frazione dell'altezza della carta); il suo
  /// bordo curvo sta poco più sotto, a [plateEdge] al centro.
  static const plateTop = 250 / 430;
  static const plateEdge = 258 / 430;

  Widget _layer(String asset) => Image.asset(
    asset,
    fit: BoxFit.fill,
    cacheWidth: decodeWidth,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: CardSkinPainter(skin),
    foregroundPainter: CardRimPainter(skin, rimWidth: rimWidth),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipPath(
          clipper: const FutCardClipper(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _layer(skin.background),
              ?figure,
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: 1 - plateTop,
                  child: _layer(skin.plate),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}
