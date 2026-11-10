import 'package:flutter/material.dart';

/// Disegna la sagoma grigia di un giocatore (testa e spalle) dentro [rect], appoggiata
/// sul fondo: per i disegni fatti a mano sulla tela (il PDF della formazione), dove
/// l'immagine dell'omino ([PlayerOmino]) non c'è.
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

/// L'omino del club: busto senza volto, grigio neutro, con la maglia rossonera. È la
/// figura di chi non ha ancora caricato la foto, sulle carte e negli avatar (immagine
/// in assets/carte/, generata da tools/carte).
const ominoAsset = 'assets/carte/omino.webp';

/// L'omino su un fondo pieno (avatar tondi, riquadri senza foto) o trasparente (carte).
class PlayerOmino extends StatelessWidget {
  const PlayerOmino({super.key, this.background});
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return ColoredBox(
      color: background ?? Colors.transparent,
      child: LayoutBuilder(
        builder: (context, box) => Image.asset(
          ominoAsset,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          // Negli avatar basta piccolo: si decodifica alla misura in cui si vede.
          cacheWidth: box.maxWidth.isFinite
              ? (box.maxWidth * dpr).ceil().clamp(48, 600)
              : null,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
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
