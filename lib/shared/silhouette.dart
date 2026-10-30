import 'package:flutter/material.dart';

/// Disegna la sagoma grigia di un giocatore (testa e spalle) dentro [rect], appoggiata
/// sul fondo: è quello che mostrano le carte FUT quando manca la foto.
void paintSilhouette(Canvas canvas, Rect rect, Color color) {
  final w = rect.width, h = rect.height;
  final cx = rect.center.dx;
  final paint = Paint()
    ..color = color
    ..isAntiAlias = true;
  // Spalle e busto: un arco largo che esce dal fondo.
  final shoulders = Path()
    ..moveTo(rect.left + w * .06, rect.bottom)
    ..cubicTo(
      rect.left + w * .08,
      rect.top + h * .74,
      rect.left + w * .24,
      rect.top + h * .66,
      cx - w * .12,
      rect.top + h * .63,
    )
    ..lineTo(cx + w * .12, rect.top + h * .63)
    ..cubicTo(
      rect.right - w * .24,
      rect.top + h * .66,
      rect.right - w * .08,
      rect.top + h * .74,
      rect.right - w * .06,
      rect.bottom,
    )
    ..close();
  canvas.drawPath(shoulders, paint);
  // Collo.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, rect.top + h * .58),
        width: w * .17,
        height: h * .14,
      ),
      Radius.circular(w * .05),
    ),
    paint,
  );
  // Testa.
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(cx, rect.top + h * .37),
      width: w * .34,
      height: h * .4,
    ),
    paint,
  );
}

/// La sagoma grigia su un fondo pieno (avatar tondi, mini carte senza foto).
class PlayerSilhouette extends StatelessWidget {
  const PlayerSilhouette({super.key, this.background, required this.color});
  final Color? background;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: background ?? Colors.transparent,
    child: CustomPaint(
      painter: SilhouettePainter(color.withValues(alpha: .55)),
      size: Size.infinite,
    ),
  );
}

class SilhouettePainter extends CustomPainter {
  const SilhouettePainter(this.color, {this.inset = .12});
  final Color color;

  /// Margine in alto, in proporzione all'altezza.
  final double inset;

  @override
  void paint(Canvas canvas, Size size) => paintSilhouette(
    canvas,
    Rect.fromLTRB(0, size.height * inset, size.width, size.height),
    color,
  );

  @override
  bool shouldRepaint(SilhouettePainter old) =>
      old.color != color || old.inset != inset;
}
