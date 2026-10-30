import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Campo verticale notturno, uguale nei due temi: erba scura e linee color oro
/// (perimetro, metà campo, cerchio e aree di rigore).
class PitchPainter extends CustomPainter {
  const PitchPainter();

  /// Margine tra il bordo del widget e le linee del campo.
  static const inset = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    canvas.drawRRect(outer, Paint()..color = MilanacColors.pitch);
    canvas.drawRRect(
      outer.deflate(.5),
      Paint()
        ..color = MilanacColors.pitchLine.withValues(alpha: .25)
        ..style = PaintingStyle.stroke,
    );

    final field = (Offset.zero & size).deflate(inset);
    final line = Paint()
      ..color = MilanacColors.pitchLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = field.width, h = field.height, l = field.left, t = field.top;
    canvas.drawRRect(
      RRect.fromRectAndRadius(field, const Radius.circular(6)),
      line,
    );
    canvas.drawLine(Offset(l, t + h / 2), Offset(l + w, t + h / 2), line);
    canvas.drawCircle(field.center, w * .12, line);

    // Aree di rigore, aperte sul lato della linea di fondo.
    final boxW = w * .47, boxH = h * .15;
    final boxL = l + (w - boxW) / 2;
    for (final top in [true, false]) {
      final base = top ? t : t + h;
      final inner = top ? base + boxH : base - boxH;
      canvas.drawPath(
        Path()
          ..moveTo(boxL, base)
          ..lineTo(boxL, inner)
          ..lineTo(boxL + boxW, inner)
          ..lineTo(boxL + boxW, base),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PitchPainter oldDelegate) => false;
}
