import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Colori della pergamena: carta avorio, inchiostro bruno, oro antico.
class ParchmentColors {
  static const paper = Color(0xFFF2E6CC);
  static const paperDark = Color(0xFFD8C094);
  static const edge = Color(0xFF6B3F16);
  static const ink = Color(0xFF3B2412);
  static const inkSoft = Color(0xFF6E4B2A);
  static const gold = Color(0xFFB08A2E);
}

/// Foglio di pergamena: carta con fibre, vignetta e bordi bruciati.
class ParchmentSheet extends StatelessWidget {
  const ParchmentSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: CustomPaint(painter: const _ParchmentPainter(), child: child),
  );
}

class _ParchmentPainter extends CustomPainter {
  const _ParchmentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = ParchmentColors.paper);

    // Fibre e macchie della carta (sempre uguali: seme fisso).
    final rnd = Random(7);
    final fleck = Paint()..color = ParchmentColors.edge.withValues(alpha: .05);
    for (var i = 0; i < 700; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        .6 + rnd.nextDouble() * 1.6,
        fleck,
      );
    }
    final fiber = Paint()
      ..color = ParchmentColors.edge.withValues(alpha: .045)
      ..strokeWidth = 1;
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 18 + rnd.nextDouble() * 60, y + rnd.nextDouble() * 4 - 2),
        fiber,
      );
    }

    // Vignetta: più scura verso i bordi.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [
            Colors.transparent,
            ParchmentColors.paperDark.withValues(alpha: .55),
            ParchmentColors.edge.withValues(alpha: .35),
          ],
          stops: const [.45, .85, 1],
        ).createShader(rect),
    );

    // Bordi bruciati: alone scuro sfumato verso l'interno e filo bruno sul contorno.
    canvas.drawRect(
      rect.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..color = ParchmentColors.edge.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ParchmentColors.edge.withValues(alpha: .8),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rullo dorato in cima e in fondo alla pergamena.
class ParchmentRod extends StatelessWidget {
  const ParchmentRod({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(9),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE8C96A), Color(0xFFB08A2E), Color(0xFF6B4E12)],
      ),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
      ],
    ),
  );
}

/// Riga decorativa: linea, stella, linea.
class ParchmentOrnament extends StatelessWidget {
  const ParchmentOrnament({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(child: Divider(color: ParchmentColors.gold, thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '✦',
            style: TextStyle(color: ParchmentColors.gold, fontSize: 14),
          ),
        ),
        Expanded(child: Divider(color: ParchmentColors.gold, thickness: 1)),
      ],
    ),
  );
}

/// Intestazione solenne: sigillo con lo stemma, titolo e motto calligrafico.
class ParchmentHeader extends StatelessWidget {
  const ParchmentHeader({
    super.key,
    required this.title,
    this.subtitle = 'Milan AC Pro Club',
    this.note,
  });
  final String title;
  final String subtitle;

  /// Riga piccola sotto il motto (es. versione e data).
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFFE8C96A), Color(0xFF8C6A1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 8)],
        ),
        child: CircleAvatar(
          radius: 38,
          backgroundColor: const Color(0xFF1A1A1A),
          child: Image.asset('assets/images/stemma_256.png', height: 60),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        title.toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: sportFont,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: 5,
          color: ParchmentColors.ink,
        ),
      ),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: scriptFont,
          fontSize: 30,
          color: ParchmentColors.inkSoft,
          height: 1.1,
        ),
      ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            note!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: serifFont,
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: ParchmentColors.inkSoft,
            ),
          ),
        ),
      const ParchmentOrnament(),
    ],
  );
}

/// Un articolo: titolo in maiuscoletto e testo con capolettera.
class ParchmentArticle extends StatelessWidget {
  const ParchmentArticle({
    super.key,
    required this.title,
    required this.body,
    this.dropCap = true,
  });
  final String title;
  final String body;
  final bool dropCap;

  @override
  Widget build(BuildContext context) {
    final paragraphs = body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: sportFont,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.8,
              color: ParchmentColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final (i, p) in paragraphs.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ParchmentParagraph(p, dropCap: dropCap && i == 0),
            ),
        ],
      ),
    );
  }
}

/// Paragrafo in Cormorant Garamond; con [dropCap] la prima lettera è grande.
class ParchmentParagraph extends StatelessWidget {
  const ParchmentParagraph(this.text, {super.key, this.dropCap = false});
  final String text;
  final bool dropCap;

  static const bodyStyle = TextStyle(
    fontFamily: serifFont,
    fontSize: 18,
    height: 1.45,
    color: ParchmentColors.ink,
  );

  @override
  Widget build(BuildContext context) {
    if (!dropCap || text.length < 2) {
      return Text(text, style: bodyStyle);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, 1),
            style: const TextStyle(
              fontFamily: serifFont,
              fontSize: 40,
              fontWeight: FontWeight.w600,
              height: .9,
              color: ParchmentColors.edge,
            ),
          ),
          TextSpan(text: text.substring(1)),
        ],
      ),
      style: bodyStyle,
    );
  }
}

/// Firma calligrafica in chiusura.
class ParchmentSignature extends StatelessWidget {
  const ParchmentSignature({super.key, this.text = 'Il Direttivo'});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontFamily: scriptFont,
            fontSize: 34,
            color: ParchmentColors.ink,
          ),
        ),
        const Text(
          'Milano siamo noi!',
          style: TextStyle(
            fontFamily: serifFont,
            fontStyle: FontStyle.italic,
            fontSize: 15,
            color: ParchmentColors.inkSoft,
          ),
        ),
      ],
    ),
  );
}
