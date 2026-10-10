import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../formazione/pitch_painter.dart';
import 'board_model.dart';

/// Colore del gettone secondo la squadra.
Color tokenColor(String side) => switch (side) {
  'futuro' => const Color(0xFF546E7A),
  'avversari' => const Color(0xFFF5F5F5),
  _ => MilanacColors.red,
};

Color tokenTextColor(String side) =>
    side == 'avversari' ? Colors.black87 : Colors.white;

/// Disegna la lavagna: campo, heatmap, frecce e gettoni (coordinate 0..1 sul campo).
class BoardPainter extends CustomPainter {
  const BoardPainter(
    this.state, {
    this.pendingArrow,
    this.selectedId,
    this.showNames = true,
  });
  final BoardState state;

  /// Freccia in corso di disegno (dal punto iniziale al dito).
  final BoardArrow? pendingArrow;
  final String? selectedId;
  final bool showNames;

  static const inset = PitchPainter.inset;

  /// Da coordinate 0..1 a pixel (e viceversa).
  static Offset toPixel(Size size, double x, double y) => Offset(
    inset + x * (size.width - inset * 2),
    inset + y * (size.height - inset * 2),
  );

  static (double, double) toField(Size size, Offset p) => (
    ((p.dx - inset) / (size.width - inset * 2)).clamp(0.0, 1.0),
    ((p.dy - inset) / (size.height - inset * 2)).clamp(0.0, 1.0),
  );

  /// Raggio di un gettone in pixel.
  static double tokenRadius(Size size) => size.width * .052;

  @override
  void paint(Canvas canvas, Size size) {
    const PitchPainter().paint(canvas, size);
    final field = (Offset.zero & size).deflate(inset);
    canvas.save();
    canvas.clipRect(field);
    _paintHeat(canvas, size);
    canvas.restore();
    for (final a in state.arrows) {
      _paintArrow(canvas, size, a, Colors.white);
    }
    if (pendingArrow != null) {
      _paintArrow(canvas, size, pendingArrow!, MilanacColors.gold);
    }
    for (final t in state.tokens) {
      _paintToken(canvas, size, t, selected: t.id == selectedId);
    }
  }

  /// Heatmap: ogni passaggio del pennello aggiunge un alone giallo; dove si insiste
  /// il centro diventa rosso.
  void _paintHeat(Canvas canvas, Size size) {
    if (state.heat.isEmpty) return;
    final r = size.width * .075;
    final yellow = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFFD600).withValues(alpha: .28), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    final red = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFF1744).withValues(alpha: .16), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * .6));
    for (final h in state.heat) {
      final c = toPixel(size, h.x, h.y);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.drawCircle(Offset.zero, r, yellow);
      canvas.drawCircle(Offset.zero, r * .6, red);
      canvas.restore();
    }
  }

  void _paintArrow(Canvas canvas, Size size, BoardArrow a, Color color) {
    final p1 = toPixel(size, a.x1, a.y1);
    final p2 = toPixel(size, a.x2, a.y2);
    if ((p2 - p1).distance < 4) return;
    final stroke = size.width * .009;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 2
      ..strokeCap = StrokeCap.round;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final dir = (p2 - p1) / (p2 - p1).distance;
    final head = size.width * .035;
    final end = p2 - dir * head * .6;
    final line = Path()..moveTo(p1.dx, p1.dy);
    if (a.dashed) {
      final total = (end - p1).distance;
      final dash = size.width * .03, gap = size.width * .018;
      var d = 0.0;
      while (d < total) {
        final s = p1 + dir * d;
        final e = p1 + dir * min(d + dash, total);
        line
          ..moveTo(s.dx, s.dy)
          ..lineTo(e.dx, e.dy);
        d += dash + gap;
      }
    } else {
      line.lineTo(end.dx, end.dy);
    }
    canvas.drawPath(line, shadow);
    canvas.drawPath(line, paint);
    // Punta.
    final n = Offset(-dir.dy, dir.dx);
    final tip = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(p2.dx - dir.dx * head + n.dx * head * .5,
          p2.dy - dir.dy * head + n.dy * head * .5)
      ..lineTo(p2.dx - dir.dx * head - n.dx * head * .5,
          p2.dy - dir.dy * head - n.dy * head * .5)
      ..close();
    canvas.drawPath(tip, Paint()..color = Colors.black.withValues(alpha: .35));
    canvas.drawPath(tip, Paint()..color = color);
  }

  void _paintToken(Canvas canvas, Size size, BoardToken t,
      {bool selected = false}) {
    final c = toPixel(size, t.x, t.y);
    final r = tokenRadius(size);
    canvas.drawCircle(
      c + Offset(0, r * .15),
      r,
      Paint()..color = Colors.black.withValues(alpha: .4),
    );
    canvas.drawCircle(c, r, Paint()..color = tokenColor(t.side));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 2
        ..color = selected ? MilanacColors.gold : Colors.white,
    );
    _text(canvas, t.label, c, r * .95, FontWeight.w700, tokenTextColor(t.side));
    if (showNames && t.name.isNotEmpty) {
      _text(
        canvas,
        t.name.toUpperCase(),
        c + Offset(0, r * 1.75),
        r * .62,
        FontWeight.w600,
        Colors.white,
        maxWidth: r * 5,
        shadow: true,
      );
    }
  }

  void _text(
    Canvas canvas,
    String s,
    Offset center,
    double fontSize,
    FontWeight weight,
    Color color, {
    double maxWidth = 200,
    bool shadow = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: sportFont,
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          letterSpacing: .3,
          shadows: shadow
              ? const [Shadow(color: Colors.black, blurRadius: 4)]
              : null,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.state != state ||
      old.pendingArrow != pendingArrow ||
      old.selectedId != selectedId ||
      old.showNames != showNames;
}

/// Il campo è alto 1 / 0.68 volte la larghezza (come la formazione).
const boardAspect = 0.68;

/// La lavagna come immagine PNG (per gli schemi salvati e la condivisione).
Future<Uint8List> renderBoardImage(BoardState state, {double width = 1080}) async {
  final size = Size(width, width / boardAspect);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  BoardPainter(state).paint(canvas, size);
  final image = await recorder.endRecording().toImage(
    size.width.round(),
    size.height.round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Anteprima statica della lavagna (nelle card e nel messaggio del replay).
class BoardPreview extends StatelessWidget {
  const BoardPreview({super.key, required this.state, this.showNames = false});
  final BoardState state;
  final bool showNames;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: boardAspect,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(painter: BoardPainter(state, showNames: showNames)),
    ),
  );
}
