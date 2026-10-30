import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../carta/card_colors.dart';
import 'trophy.dart';

/// Trofeo dorato disegnato in base alla forma scelta.
class TrophyShapePainter extends CustomPainter {
  const TrophyShapePainter(this.shape);
  final TrophyShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          CardColors.metalLight,
          CardColors.metal,
          CardColors.metalDeep,
          CardColors.metalWarm,
        ],
        stops: [0, .4, .75, 1],
      ).createShader(rect);
    final dark = Paint()..color = CardColors.trophyBase;
    // Dettagli neri sull'oro: i trofei del club sono neri e oro.
    final black = Paint()..color = MilanacColors.ink;
    final shine = Paint()..color = MilanacColors.ivory.withValues(alpha: .45);

    switch (shape) {
      case TrophyShape.coppa:
        // Base a due livelli.
        canvas.drawRect(Rect.fromLTWH(w * .2, h * .86, w * .6, h * .14), dark);
        canvas.drawRect(Rect.fromLTWH(w * .25, h * .88, w * .5, h * .03), gold);
        canvas.drawRect(Rect.fromLTWH(w * .3, h * .76, w * .4, h * .1), gold);
        // Stelo.
        canvas.drawRect(Rect.fromLTWH(w * .45, h * .55, w * .1, h * .22), gold);
        // Coppa.
        canvas.drawPath(
          Path()
            ..moveTo(w * .15, h * .05)
            ..lineTo(w * .85, h * .05)
            ..quadraticBezierTo(w * .85, h * .55, w * .5, h * .58)
            ..quadraticBezierTo(w * .15, h * .55, w * .15, h * .05)
            ..close(),
          gold,
        );
        // Manici.
        final handle = Paint()
          ..shader = gold.shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .06;
        canvas.drawArc(
          Rect.fromLTWH(0, h * .1, w * .3, h * .3),
          pi * .5,
          pi,
          false,
          handle,
        );
        canvas.drawArc(
          Rect.fromLTWH(w * .7, h * .1, w * .3, h * .3),
          -pi * .5,
          pi,
          false,
          handle,
        );
        canvas.drawRect(
          Rect.fromLTWH(w * .15, h * .14, w * .7, h * .04),
          black,
        );
        canvas.drawRect(
          Rect.fromLTWH(w * .25, h * .1, w * .06, h * .35),
          shine,
        );
      case TrophyShape.targa:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * .1, h * .05, w * .8, h * .9),
            Radius.circular(w * .08),
          ),
          dark,
        );
        canvas.drawOval(Rect.fromLTWH(w * .2, h * .15, w * .6, h * .55), gold);
        canvas.drawOval(
          Rect.fromLTWH(w * .32, h * .26, w * .36, h * .33),
          black,
        );
        canvas.drawRect(Rect.fromLTWH(w * .22, h * .76, w * .56, h * .1), gold);
      case TrophyShape.medaglia:
        // Nastro nero e oro.
        canvas.drawPath(
          Path()
            ..moveTo(w * .25, 0)
            ..lineTo(w * .45, 0)
            ..lineTo(w * .55, h * .45)
            ..lineTo(w * .42, h * .45)
            ..close(),
          black,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * .55, 0)
            ..lineTo(w * .75, 0)
            ..lineTo(w * .58, h * .45)
            ..lineTo(w * .45, h * .45)
            ..close(),
          gold,
        );
        canvas.drawCircle(Offset(w * .5, h * .68), w * .3, gold);
        canvas.drawCircle(
          Offset(w * .5, h * .68),
          w * .22,
          Paint()
            ..color = CardColors.metalDeep
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        _star(
          canvas,
          Offset(w * .5, h * .68),
          w * .14,
          Paint()..color = CardColors.metalLight,
        );
      case TrophyShape.scudetto:
        final shield = Path()
          ..moveTo(w * .12, h * .08)
          ..lineTo(w * .88, h * .08)
          ..lineTo(w * .88, h * .5)
          ..quadraticBezierTo(w * .88, h * .82, w * .5, h * .95)
          ..quadraticBezierTo(w * .12, h * .82, w * .12, h * .5)
          ..close();
        canvas.drawPath(shield, gold);
        canvas.save();
        canvas.clipPath(shield);
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(w * (.2 + i * .22), h * .18, w * .11, h * .8),
            black,
          );
        }
        canvas.restore();
        canvas.drawPath(
          shield,
          Paint()
            ..shader = gold.shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * .07,
        );
      case TrophyShape.stella:
        canvas.drawRect(Rect.fromLTWH(w * .3, h * .82, w * .4, h * .16), dark);
        canvas.drawRect(Rect.fromLTWH(w * .46, h * .62, w * .08, h * .2), gold);
        _star(canvas, Offset(w * .5, h * .36), w * .45, gold);
        _star(canvas, Offset(w * .5, h * .36), w * .2, black);
    }
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * .45;
      final a = -pi / 2 + i * pi / 5;
      final pt = c + Offset(cos(a) * radius, sin(a) * radius);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(covariant TrophyShapePainter old) => old.shape != shape;
}
