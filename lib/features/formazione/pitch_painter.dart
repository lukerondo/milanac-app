import 'dart:math';

import 'package:flutter/material.dart';

/// Campo verticale stile San Siro: erba a strisce, linee bianche,
/// tribune rossonere sui bordi e luce dei riflettori.
class PitchPainter extends CustomPainter {
  const PitchPainter();

  /// Margine tra bordo del widget e linee del campo (spazio per le tribune).
  static const inset = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;

    // Tribune: strisce rossonere verticali.
    final stands = Paint();
    const stripe = 10.0;
    for (var x = 0.0; x < size.width; x += stripe) {
      stands.color = (x ~/ stripe).isEven
          ? const Color(0xFF8E0B20)
          : const Color(0xFF111111);
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, size.height), stands);
    }

    final field = outer.deflate(inset);
    final rr = RRect.fromRectAndRadius(field, const Radius.circular(6));
    canvas.save();
    canvas.clipRRect(rr);

    // Erba a bande orizzontali.
    const bands = 12;
    final bandH = field.height / bands;
    for (var i = 0; i < bands; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          field.left,
          field.top + i * bandH,
          field.width,
          bandH + 1,
        ),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF2E7D32)
              : const Color(0xFF388E3C),
      );
    }

    // Riflettori: alone luminoso ai quattro angoli.
    for (final c in [
      field.topLeft,
      field.topRight,
      field.bottomLeft,
      field.bottomRight,
    ]) {
      canvas.drawCircle(
        c,
        field.width * .7,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withValues(alpha: .13), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: field.width * .7)),
      );
    }
    canvas.restore();

    // Linee.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final w = field.width, h = field.height, l = field.left, t = field.top;
    canvas.drawRect(field, line);
    canvas.drawLine(Offset(l, t + h / 2), Offset(l + w, t + h / 2), line);
    canvas.drawCircle(field.center, w * .15, line);
    canvas.drawCircle(field.center, 3, line..style = PaintingStyle.fill);
    line.style = PaintingStyle.stroke;

    for (final top in [true, false]) {
      final dir = top ? 1.0 : -1.0;
      final base = top ? t : t + h;
      // Area di rigore e area piccola.
      final boxW = w * .6, boxH = h * .16;
      final smallW = w * .28, smallH = h * .06;
      canvas.drawRect(
        Rect.fromLTWH(l + (w - boxW) / 2, top ? base : base - boxH, boxW, boxH),
        line,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          l + (w - smallW) / 2,
          top ? base : base - smallH,
          smallW,
          smallH,
        ),
        line,
      );
      // Dischetto e lunetta.
      final spot = Offset(l + w / 2, base + dir * h * .11);
      canvas.drawCircle(spot, 2.5, Paint()..color = Colors.white);
      final arcR = w * .13;
      canvas.drawArc(
        Rect.fromCircle(center: spot, radius: arcR),
        top ? pi * .2 : pi * 1.2,
        pi * .6,
        false,
        line,
      );
      // Porta.
      final goalW = w * .16;
      canvas.drawRect(
        Rect.fromLTWH(l + (w - goalW) / 2, top ? base - 6 : base, goalW, 6),
        Paint()..color = Colors.white.withValues(alpha: .9),
      );
    }

    // Bandierine (archi d'angolo).
    for (final (c, start) in [
      (field.topLeft, 0.0),
      (field.topRight, pi / 2),
      (field.bottomRight, pi),
      (field.bottomLeft, pi * 1.5),
    ]) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 10),
        start,
        pi / 2,
        false,
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PitchPainter oldDelegate) => false;
}
