import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Il campo in prospettiva, come il menu tattiche di FC: la porta avversaria lontana in
/// alto, la nostra vicina in basso. [project] porta un punto del campo (x e y da 0 a 1,
/// come i posti dei moduli) sullo schermo; [nearness] dice quanto è vicino (da 0 in
/// fondo a 1 davanti), per ingrandire le carte più vicine.
class PitchPerspective {
  const PitchPerspective(this.size);
  final Size size;

  /// Quante volte la linea di fondo vicina è più larga di quella lontana.
  static const ratio = 1.55;

  /// Spazio sopra il campo (per le carte in piedi degli attaccanti), sotto e ai lati.
  static const topPad = 64.0, bottomPad = 12.0, sidePad = 6.0;

  double _depth(double y) => 1 + (ratio - 1) * (1 - y);

  Offset project(double x, double y) {
    final top = topPad, bottom = size.height - bottomPad;
    // Proiezione vera: le righe lontane si stringono e si avvicinano tra loro.
    final b = (bottom - top) / (1 - 1 / ratio);
    final z = _depth(y);
    final width = (size.width - 2 * sidePad) / z;
    return Offset(size.width / 2 + (x - .5) * width, bottom - b + b / z);
  }

  /// Quanto è grande una carta a una certa [nearness]: in fondo al campo il 70%.
  static double cardScaleAt(double nearness) => .7 + .3 * nearness;

  double nearness(double y) => (1 / _depth(y) - 1 / ratio) / (1 - 1 / ratio);
}

/// Erba a strisce, linee d'oro proiettate (perimetro, metà campo, cerchio, aree e
/// dischetti) e la luce dei riflettori dall'alto. Uguale nei due temi.
class PerspectivePitchPainter extends CustomPainter {
  const PerspectivePitchPainter();

  /// Proporzioni del campo vero (larghezza / lunghezza), per il cerchio di centrocampo.
  static const _aspect = .66;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = PitchPerspective(size);
    final rect = Offset.zero & size;
    final clip = RRect.fromRectAndRadius(rect, const Radius.circular(18));
    canvas
      ..save()
      ..clipRRect(clip);
    // Il buio dello stadio intorno al campo.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MilanacColors.black, Color(0xFF07140D)],
        ).createShader(rect),
    );
    // Strisce dell'erba, alternate come quelle tagliate.
    const stripes = 14;
    final light = Color.lerp(MilanacColors.pitch, Colors.white, .05)!;
    for (var i = 0; i < stripes; i++) {
      final y0 = i / stripes, y1 = (i + 1) / stripes;
      canvas.drawPath(
        _quad(pitch, 0, y0, 1, y1),
        Paint()..color = i.isEven ? MilanacColors.pitch : light,
      );
    }
    final line = Paint()
      ..color = MilanacColors.pitchLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(_quad(pitch, 0, 0, 1, 1), line)
      ..drawPath(_quad(pitch, 0, .5, 1, .5), line);
    // Cerchio di centrocampo: un'ellisse schiacciata dalla distanza.
    const r = .13;
    final circle = Path();
    for (var i = 0; i <= 48; i++) {
      final a = i / 48 * 2 * math.pi;
      final p = pitch.project(
        .5 + r * math.cos(a),
        .5 + r * _aspect * math.sin(a),
      );
      i == 0 ? circle.moveTo(p.dx, p.dy) : circle.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(circle, line);
    // Aree di rigore e piccole aree, aperte sulla linea di fondo; i dischetti.
    final dot = Paint()..color = MilanacColors.pitchLine;
    for (final far in [true, false]) {
      for (final (w, h) in const [(.5, .16), (.24, .06)]) {
        final edge = far ? 0.0 : 1.0;
        final inner = far ? h : 1 - h;
        final l = (1 - w) / 2, r = (1 + w) / 2;
        final path = Path();
        for (final (i, (x, y)) in [
          (l, edge),
          (l, inner),
          (r, inner),
          (r, edge),
        ].indexed) {
          final p = pitch.project(x, y);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, line);
      }
      final spot = pitch.project(.5, far ? .11 : .89);
      canvas.drawCircle(spot, 1.5 + pitch.nearness(far ? .11 : .89), dot);
    }
    canvas.drawCircle(pitch.project(.5, .5), 2, dot);
    // La luce dei riflettori che scende sul campo.
    final glow = Rect.fromCenter(
      center: Offset(size.width / 2, 0),
      width: size.width * 1.4,
      height: size.height * 1.1,
    );
    canvas
      ..drawOval(
        glow,
        Paint()
          ..shader = RadialGradient(
            colors: [
              MilanacColors.goldLight.withValues(alpha: .10),
              MilanacColors.goldLight.withValues(alpha: 0),
            ],
          ).createShader(glow),
      )
      ..restore()
      ..drawRRect(
        clip.deflate(.5),
        Paint()
          ..color = MilanacColors.pitchLine.withValues(alpha: .25)
          ..style = PaintingStyle.stroke,
      );
  }

  /// Il quadrilatero del campo tra (x0, y0) e (x1, y1), proiettato.
  Path _quad(PitchPerspective p, double x0, double y0, double x1, double y1) {
    final a = p.project(x0, y0), b = p.project(x1, y0);
    final c = p.project(x1, y1), d = p.project(x0, y1);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
  }

  @override
  bool shouldRepaint(covariant PerspectivePitchPainter oldDelegate) => false;
}

/// Le ombre delle carte sull'erba, sotto i piedi di ognuna.
class CardShadowsPainter extends CustomPainter {
  const CardShadowsPainter(this.points);

  /// Punto del campo (x, y da 0 a 1) di ogni carta.
  final List<(double, double)> points;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = PitchPerspective(size);
    final shadow = Paint()
      ..color = MilanacColors.black.withValues(alpha: .45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final (x, y) in points) {
      final s = PitchPerspective.cardScaleAt(pitch.nearness(y));
      canvas.drawOval(
        Rect.fromCenter(
          center: pitch.project(x, y),
          width: 40 * s,
          height: 10 * s,
        ),
        shadow,
      );
    }
  }

  @override
  bool shouldRepaint(CardShadowsPainter old) => old.points != points;
}
