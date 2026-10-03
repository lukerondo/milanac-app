import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'trophy.dart';

/// Proporzioni della scena (larghezza / altezza) e posizione della bacheca.
const sceneAspect = 0.62;
const cabinetRect = Rect.fromLTRB(.17, .05, .87, .80);

/// Rettangolo interno (vetro) della bacheca, in coordinate relative alla scena.
Rect cabinetInner(Size s) {
  final c = Rect.fromLTRB(
    cabinetRect.left * s.width,
    cabinetRect.top * s.height,
    cabinetRect.right * s.width,
    cabinetRect.bottom * s.height,
  );
  return c.deflate(c.width * .06);
}

/// Sfondo: parete di velluto rosso, stendardi rossoneri, pavimento di marmo e bacheca.
class TrophyRoomPainter extends CustomPainter {
  const TrophyRoomPainter({required this.shelves});
  final int shelves;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final floorY = h * .80;

    // Parete.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, floorY),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.3),
          radius: 1.1,
          colors: [Color(0xFF5A0A16), Color(0xFF2A0509), Color(0xFF0B0B0D)],
        ).createShader(Rect.fromLTWH(0, 0, w, floorY)),
    );
    // Pieghe del velluto.
    final fold = Paint()..color = Colors.black.withValues(alpha: .12);
    for (var x = 0.0; x < w; x += w / 14) {
      canvas.drawRect(Rect.fromLTWH(x, 0, w / 40, floorY), fold);
    }
    // Stendardi rossoneri ai lati.
    for (final left in [w * .02, w * .90]) {
      final banner = Rect.fromLTWH(left, h * .04, w * .08, h * .42);
      canvas.save();
      canvas.clipPath(
        Path()
          ..moveTo(banner.left, banner.top)
          ..lineTo(banner.right, banner.top)
          ..lineTo(banner.right, banner.bottom)
          ..lineTo(banner.center.dx, banner.bottom - banner.width * .5)
          ..lineTo(banner.left, banner.bottom)
          ..close(),
      );
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            banner.left + i * banner.width / 4,
            banner.top,
            banner.width / 4,
            banner.height,
          ),
          Paint()..color = i.isEven ? MilanacColors.red : Colors.black,
        );
      }
      canvas.restore();
      canvas.drawLine(
        Offset(banner.left - 2, banner.top),
        Offset(banner.right + 2, banner.top),
        Paint()
          ..color = MilanacColors.gold
          ..strokeWidth = 3,
      );
    }

    // Pavimento di marmo nero con riflesso.
    final floor = Rect.fromLTWH(0, floorY, w, h - floorY);
    canvas.drawRect(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C1416), Color(0xFF050505)],
        ).createShader(floor),
    );
    final vein = Paint()
      ..color = MilanacColors.gold.withValues(alpha: .10)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rnd = Random(7);
    for (var i = 0; i < 6; i++) {
      final y = floorY + rnd.nextDouble() * (h - floorY);
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(
            w * .5,
            y + (rnd.nextDouble() - .5) * 40,
            w,
            y + (rnd.nextDouble() - .5) * 30,
          ),
        vein,
      );
    }

    // Bacheca: cornice in legno scuro con profili oro.
    final cab = Rect.fromLTRB(
      cabinetRect.left * w,
      cabinetRect.top * h,
      cabinetRect.right * w,
      cabinetRect.bottom * h,
    );
    canvas.drawRect(
      cab.shift(const Offset(0, 6)).inflate(4),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cab, const Radius.circular(6)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2B1A12), Color(0xFF4A2E1E), Color(0xFF2B1A12)],
        ).createShader(cab),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cab, const Radius.circular(6)),
      Paint()
        ..color = MilanacColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Frontone.
    canvas.drawRect(
      Rect.fromLTWH(cab.left - 6, cab.top - 10, cab.width + 12, 12),
      Paint()..color = const Color(0xFF3A2418),
    );
    canvas.drawRect(
      Rect.fromLTWH(cab.left - 6, cab.top - 10, cab.width + 12, 3),
      Paint()..color = MilanacColors.gold,
    );

    // Interno illuminato.
    final inner = cabinetInner(size);
    canvas.drawRect(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A1A12), Color(0xFF1A0C08)],
        ).createShader(inner),
    );

    // Mensole con faretti.
    final shelfH = inner.height / shelves;
    for (var i = 0; i < shelves; i++) {
      final top = inner.top + i * shelfH;
      final shelfY = top + shelfH - 6;
      // Cono di luce dal faretto.
      final cone = Path()
        ..moveTo(inner.center.dx - 6, top + 2)
        ..lineTo(inner.center.dx + 6, top + 2)
        ..lineTo(inner.right - 4, shelfY)
        ..lineTo(inner.left + 4, shelfY)
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFE6A8).withValues(alpha: .28),
              const Color(0xFFFFE6A8).withValues(alpha: .04),
            ],
          ).createShader(Rect.fromLTRB(inner.left, top, inner.right, shelfY)),
      );
      canvas.drawCircle(
        Offset(inner.center.dx, top + 3),
        3,
        Paint()..color = const Color(0xFFFFF4D6),
      );
      // Ripiano di vetro.
      canvas.drawRect(
        Rect.fromLTRB(inner.left, shelfY, inner.right, shelfY + 5),
        Paint()..color = Colors.white.withValues(alpha: .35),
      );
      canvas.drawRect(
        Rect.fromLTRB(inner.left, shelfY + 5, inner.right, shelfY + 7),
        Paint()..color = MilanacColors.gold.withValues(alpha: .6),
      );
    }

    // Riflesso del vetro.
    canvas.drawPath(
      Path()
        ..moveTo(inner.left + inner.width * .55, inner.top)
        ..lineTo(inner.left + inner.width * .70, inner.top)
        ..lineTo(inner.left + inner.width * .35, inner.bottom)
        ..lineTo(inner.left + inner.width * .20, inner.bottom)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .05),
    );
  }

  @override
  bool shouldRepaint(covariant TrophyRoomPainter old) => old.shelves != shelves;
}

/// Giocatore del Pro Club visto di spalle che guarda la bacheca.
class AdmiringPlayerPainter extends CustomPainter {
  const AdmiringPlayerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    // Ombra a terra.
    canvas.drawOval(
      Rect.fromCenter(center: p(.5, .97), width: w * .7, height: h * .05),
      Paint()
        ..color = Colors.black.withValues(alpha: .6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    final skin = Paint()..color = const Color(0xFFC68E6A);
    // Gambe e calzettoni.
    for (final x in [.36, .58]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * w, .66 * h, .12 * w, .14 * h),
          const Radius.circular(6),
        ),
        skin,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * w - 1, .78 * h, .13 * w, .15 * h),
          const Radius.circular(5),
        ),
        Paint()..color = Colors.black,
      );
      canvas.drawRect(
        Rect.fromLTWH(x * w - 1, .80 * h, .13 * w, .02 * h),
        Paint()..color = MilanacColors.red,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * w - 3, .92 * h, .17 * w, .05 * h),
          const Radius.circular(8),
        ),
        Paint()..color = const Color(0xFF111111),
      );
    }

    // Pantaloncini.
    canvas.drawPath(
      Path()
        ..moveTo(.30 * w, .54 * h)
        ..lineTo(.72 * w, .54 * h)
        ..lineTo(.74 * w, .70 * h)
        ..lineTo(.52 * w, .70 * h)
        ..lineTo(.50 * w, .64 * h)
        ..lineTo(.48 * w, .70 * h)
        ..lineTo(.28 * w, .70 * h)
        ..close(),
      Paint()..color = Colors.white,
    );

    // Braccia (una sul fianco).
    canvas.drawPath(
      Path()
        ..moveTo(.20 * w, .26 * h)
        ..quadraticBezierTo(.08 * w, .42 * h, .20 * w, .52 * h)
        ..lineTo(.28 * w, .50 * h)
        ..quadraticBezierTo(.20 * w, .42 * h, .28 * w, .30 * h)
        ..close(),
      skin,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.80 * w, .26 * h)
        ..quadraticBezierTo(.94 * w, .44 * h, .84 * w, .58 * h)
        ..lineTo(.77 * w, .56 * h)
        ..quadraticBezierTo(.84 * w, .44 * h, .72 * w, .30 * h)
        ..close(),
      skin,
    );

    // Maglia rossonera a strisce verticali.
    final shirt = Path()
      ..moveTo(.30 * w, .17 * h)
      ..quadraticBezierTo(.50 * w, .14 * h, .70 * w, .17 * h)
      ..lineTo(.86 * w, .24 * h)
      ..lineTo(.80 * w, .34 * h)
      ..lineTo(.74 * w, .31 * h)
      ..lineTo(.73 * w, .56 * h)
      ..lineTo(.29 * w, .56 * h)
      ..lineTo(.28 * w, .31 * h)
      ..lineTo(.20 * w, .34 * h)
      ..lineTo(.14 * w, .24 * h)
      ..close();
    canvas.save();
    canvas.clipPath(shirt);
    const stripes = 9;
    for (var i = 0; i < stripes; i++) {
      canvas.drawRect(
        Rect.fromLTWH((.12 + i * .08) * w, .1 * h, .08 * w, .5 * h),
        Paint()..color = i.isEven ? MilanacColors.red : const Color(0xFF111111),
      );
    }
    // Luce della bacheca sulla schiena (in alto a destra).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.8, -1),
          radius: 1,
          colors: [
            const Color(0xFFFFE6A8).withValues(alpha: .35),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.restore();

    // Nome e numero sulla schiena.
    void label(String text, double y, double fontSize) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w * .505 - tp.width / 2, y * h));
    }

    label('MILANAC', .21, w * .085);
    label('10', .27, w * .2);

    // Collo e testa (leggermente girata verso la bacheca, in alto a destra).
    canvas.drawRect(Rect.fromLTWH(.45 * w, .12 * h, .11 * w, .05 * h), skin);
    canvas.save();
    canvas.translate(.52 * w, .08 * h);
    canvas.rotate(.12);
    // Visto di spalle: orecchio, poi nuca coperta dai capelli.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(.12 * w, .012 * h),
        width: .045 * w,
        height: .05 * h,
      ),
      skin,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: .26 * w, height: .15 * h),
      Paint()..color = const Color(0xFF1E140E),
    );
    // Sfumatura della nuca.
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(0, .035 * h),
        width: .2 * w,
        height: .08 * h,
      ),
      0,
      pi,
      true,
      Paint()..color = const Color(0xFF3A2A20),
    );
    // Riflesso della luce della bacheca sui capelli.
    canvas.drawArc(
      Rect.fromCenter(center: Offset.zero, width: .22 * w, height: .12 * h),
      -pi * .45,
      pi * .35,
      false,
      Paint()
        ..color = const Color(0xFFFFE6A8).withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();

    // Contorno luminoso (rim light).
    canvas.drawPath(
      shirt,
      Paint()
        ..color = const Color(0xFFFFE6A8).withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
          Color(0xFFFFF1B8),
          Color(0xFFD4AF37),
          Color(0xFF8A6A12),
          Color(0xFFE9C960),
        ],
        stops: [0, .4, .75, 1],
      ).createShader(rect);
    final dark = Paint()..color = const Color(0xFF2B1A12);
    final red = Paint()..color = MilanacColors.red;
    final shine = Paint()..color = Colors.white.withValues(alpha: .45);

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
        canvas.drawRect(Rect.fromLTWH(w * .15, h * .14, w * .7, h * .04), red);
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
        canvas.drawOval(Rect.fromLTWH(w * .32, h * .26, w * .36, h * .33), red);
        canvas.drawRect(Rect.fromLTWH(w * .22, h * .76, w * .56, h * .1), gold);
      case TrophyShape.medaglia:
        // Nastro rossonero.
        canvas.drawPath(
          Path()
            ..moveTo(w * .25, 0)
            ..lineTo(w * .45, 0)
            ..lineTo(w * .55, h * .45)
            ..lineTo(w * .42, h * .45)
            ..close(),
          red,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * .55, 0)
            ..lineTo(w * .75, 0)
            ..lineTo(w * .58, h * .45)
            ..lineTo(w * .45, h * .45)
            ..close(),
          Paint()..color = Colors.black,
        );
        canvas.drawCircle(Offset(w * .5, h * .68), w * .3, gold);
        canvas.drawCircle(
          Offset(w * .5, h * .68),
          w * .22,
          Paint()
            ..color = const Color(0xFF8A6A12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        _star(
          canvas,
          Offset(w * .5, h * .68),
          w * .14,
          Paint()..color = const Color(0xFFFFF1B8),
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
            Paint()..color = MilanacColors.red,
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
        _star(canvas, Offset(w * .5, h * .36), w * .2, red);
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
