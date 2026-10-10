import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'face.dart';

/// Tonalità della pelle, nell'ordine di [FacePart.skin].
const faceSkinColors = [
  Color(0xFFF6D6C2),
  Color(0xFFF0C2A8),
  Color(0xFFD9A982),
  Color(0xFFC68B59),
  Color(0xFF9A6240),
  Color(0xFF6B4428),
];

/// Colori dei capelli, nell'ordine di [FacePart.hairColor].
const faceHairColors = [
  Color(0xFF1B1B1F),
  Color(0xFF5A3A22),
  Color(0xFFD9B35B),
  Color(0xFFB4472A),
  Color(0xFF9A9A9A),
  Color(0xFFE8E2D0),
];

/// Colori degli occhi, nell'ordine di [FacePart.eyeColor].
const faceEyeColors = [
  Color(0xFF5B3A1E),
  Color(0xFF4A90C9),
  Color(0xFF4F9A5E),
  Color(0xFF8C6A3A),
];

/// Quanto volto mostrare: il busto con la maglia rossonera, o solo la testa (avatar tondi).
enum FaceCrop { bust, head }

/// Il volto del giocatore disegnato dai parametri di [Face]: niente immagini, solo forme.
class FaceView extends StatelessWidget {
  const FaceView({
    super.key,
    required this.face,
    this.size = 120,
    this.crop = FaceCrop.bust,
    this.background,
  });

  final Face face;
  final double size;
  final FaceCrop crop;

  /// Colore di fondo (null = trasparente).
  final Color? background;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(size),
      painter: FacePainter(face, crop: crop, background: background),
    ),
  );
}

/// Disegna il volto in un quadrato di 200×200 unità, poi scalato alla dimensione reale.
class FacePainter extends CustomPainter {
  const FacePainter(this.face, {this.crop = FaceCrop.bust, this.background});

  final Face face;
  final FaceCrop crop;
  final Color? background;

  static const _unit = 200.0;

  Color get _skin => faceSkinColors[face.skin];
  Color get _hair => faceHairColors[face.hairColor];
  Color get _eye => faceEyeColors[face.eyeColor];
  Color get _skinShadow => Color.lerp(_skin, Colors.black, .18)!;
  Color get _skinLight => Color.lerp(_skin, Colors.white, .18)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background!);
    }
    canvas.save();
    // Scala e inquadratura.
    final scale = size.shortestSide / _unit;
    canvas.translate(
      (size.width - _unit * scale) / 2,
      (size.height - _unit * scale) / 2,
    );
    canvas.scale(scale);
    if (crop == FaceCrop.head) {
      // Ingrandisce la sola testa (quadrato 40..160 × 26..146) a tutto il riquadro.
      const focus = Rect.fromLTRB(40, 26, 160, 146);
      final s = _unit / focus.width;
      canvas.scale(s);
      canvas.translate(-focus.left, -focus.top);
      canvas.clipRect(focus.inflate(60));
    }

    final fill = Paint()..style = PaintingStyle.fill;
    final head = _headPath();

    // 1) Capelli lunghi: dietro la testa.
    if (face.hair == 5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(46, 44, 154, 158),
          const Radius.circular(34),
        ),
        fill..color = _hair,
      );
    }

    // 2) Maglia rossonera con colletto.
    if (crop == FaceCrop.bust) {
      _paintJersey(canvas);
    }

    // 3) Collo e orecchie.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(84, 118, 116, 164),
        const Radius.circular(12),
      ),
      fill..color = _skinShadow,
    );
    for (final cx in [50.0, 150.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 96), width: 16, height: 22),
        fill..color = _skin,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 97), width: 7, height: 11),
        fill..color = _skinShadow.withValues(alpha: .5),
      );
    }

    // 4) Testa.
    canvas.drawPath(head, fill..color = _skin);
    // Luce sulla fronte.
    canvas.drawOval(
      const Rect.fromLTRB(70, 50, 130, 86),
      fill..color = _skinLight.withValues(alpha: .35),
    );

    // 5) Barba (sotto bocca e naso).
    _paintBeard(canvas, head);

    // 6) Sopracciglia, occhi, naso, bocca.
    _paintBrows(canvas);
    _paintEyes(canvas);
    _paintNose(canvas);
    _paintMouth(canvas);

    // 7) Capelli davanti.
    _paintHair(canvas, head);

    // 8) Accessori.
    _paintAccessory(canvas);

    canvas.restore();
  }

  Path _headPath() => Path()
    ..moveTo(100, 36)
    ..cubicTo(132, 36, 148, 62, 148, 92)
    ..cubicTo(148, 124, 126, 150, 100, 150)
    ..cubicTo(74, 150, 52, 124, 52, 92)
    ..cubicTo(52, 62, 68, 36, 100, 36)
    ..close();

  void _paintJersey(Canvas canvas) {
    final jersey = Path()
      ..moveTo(14, 200)
      ..cubicTo(14, 166, 56, 150, 100, 150)
      ..cubicTo(144, 150, 186, 166, 186, 200)
      ..close();
    canvas.save();
    canvas.clipPath(jersey);
    // Strisce verticali rosse e nere.
    for (var x = 14.0; x < 186; x += 24) {
      canvas.drawRect(
        Rect.fromLTWH(x, 150, 12, 50),
        Paint()..color = MilanacColors.red,
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 12, 150, 12, 50),
        Paint()..color = const Color(0xFF151515),
      );
    }
    // Ombra sotto il collo.
    canvas.drawOval(
      const Rect.fromLTRB(70, 148, 130, 170),
      Paint()..color = Colors.black.withValues(alpha: .25),
    );
    canvas.restore();
    // Colletto bianco.
    canvas.drawPath(
      Path()
        ..moveTo(76, 154)
        ..quadraticBezierTo(100, 176, 124, 154)
        ..quadraticBezierTo(100, 170, 76, 154)
        ..close(),
      Paint()..color = const Color(0xFFF2F2F2),
    );
    // Bordo oro delle spalle.
    canvas.drawPath(
      jersey,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = MilanacColors.gold.withValues(alpha: .6),
    );
  }

  Path _capPath({double left = 84, double right = 84, double center = 62}) =>
      Path()
        ..moveTo(52, 92)
        ..cubicTo(52, 54, 68, 28, 100, 28)
        ..cubicTo(132, 28, 148, 54, 148, 92)
        ..lineTo(148, right)
        ..cubicTo(140, center + 8, 126, center, 100, center)
        ..cubicTo(74, center, 60, center + 8, 52, left)
        ..close();

  void _paintHair(Canvas canvas, Path head) {
    final paint = Paint()..color = _hair;
    final light = Paint()..color = Colors.white.withValues(alpha: .14);
    switch (face.hair) {
      case 0: // Rasati: solo un'ombra di capelli.
        canvas.drawPath(
          _capPath(),
          Paint()..color = _hair.withValues(alpha: .45),
        );
      case 1: // Corti.
        canvas.drawPath(_capPath(), paint);
        canvas.drawOval(const Rect.fromLTRB(72, 32, 118, 48), light);
      case 2: // Ciuffo.
        canvas.drawPath(_capPath(center: 64), paint);
        canvas.drawOval(const Rect.fromLTRB(58, 26, 112, 62), paint);
        canvas.drawOval(const Rect.fromLTRB(66, 30, 100, 44), light);
      case 3: // Riga laterale.
        canvas.drawPath(_capPath(left: 78, right: 92, center: 60), paint);
        canvas.drawPath(
          Path()
            ..moveTo(88, 30)
            ..quadraticBezierTo(62, 46, 56, 76),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = _skin.withValues(alpha: .7),
        );
        canvas.drawOval(const Rect.fromLTRB(96, 32, 140, 50), light);
      case 4: // Ricci.
        canvas.drawPath(_capPath(center: 64), paint);
        for (final (cx, cy) in [
          (58.0, 80.0),
          (62.0, 60.0),
          (72.0, 44.0),
          (86.0, 34.0),
          (100.0, 30.0),
          (114.0, 34.0),
          (128.0, 44.0),
          (138.0, 60.0),
          (142.0, 80.0),
        ]) {
          canvas.drawCircle(Offset(cx, cy), 11, paint);
        }
        canvas.drawCircle(const Offset(86, 44), 5, light);
      case 5: // Lunghi: davanti una frangia morbida.
        canvas.drawPath(_capPath(left: 90, right: 90, center: 66), paint);
        canvas.drawOval(const Rect.fromLTRB(76, 32, 124, 48), light);
      case 6: // Cresta.
        canvas.drawPath(
          _capPath(),
          Paint()..color = _hair.withValues(alpha: .45),
        );
        canvas.drawPath(
          Path()
            ..moveTo(88, 66)
            ..lineTo(84, 24)
            ..quadraticBezierTo(100, 4, 116, 24)
            ..lineTo(112, 66)
            ..close(),
          paint,
        );
      case 7: // Chignon.
        canvas.drawPath(_capPath(center: 64), paint);
        canvas.drawCircle(const Offset(100, 30), 14, paint);
        canvas.drawCircle(const Offset(96, 26), 5, light);
      case 8: // Calvo: una luce sulla testa.
        canvas.drawOval(const Rect.fromLTRB(78, 38, 112, 54), light);
    }
  }

  void _paintBrows(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = face.brows == 1 ? 5.5 : 3.5
      ..color = _hair;
    final tilt = face.brows == 2 ? 5.0 : 0.0; // decise: interno più basso
    canvas.drawPath(
      Path()
        ..moveTo(66, 78)
        ..quadraticBezierTo(79, 71, 92, 76 + tilt),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(134, 78)
        ..quadraticBezierTo(121, 71, 108, 76 + tilt),
      paint,
    );
  }

  void _paintEyes(Canvas canvas) {
    final (rx, ry) = switch (face.eyes) {
      1 => (10.5, 4.5), // allungati
      2 => (10.5, 7.5), // grandi
      3 => (9.5, 3.6), // socchiusi
      _ => (9.0, 6.0),
    };
    for (final cx in [80.0, 120.0]) {
      final center = Offset(cx, 93);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        Paint()..color = const Color(0xFFFAFAFA),
      );
      final iris = ry < 4.5 ? ry - .2 : 4.6;
      canvas.drawCircle(center, iris, Paint()..color = _eye);
      canvas.drawCircle(
        center,
        iris * .5,
        Paint()..color = const Color(0xFF151515),
      );
      canvas.drawCircle(
        center.translate(-1.6, -1.6),
        1.3,
        Paint()..color = Colors.white,
      );
      // Palpebra superiore.
      canvas.drawPath(
        Path()
          ..moveTo(cx - rx, 93)
          ..quadraticBezierTo(cx, 93 - ry * 2.2, cx + rx, 93),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = face.eyes == 3 ? 2.6 : 1.8
          ..strokeCap = StrokeCap.round
          ..color = _skinShadow,
      );
    }
  }

  void _paintNose(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(100, 95)
        ..lineTo(96, 109)
        ..quadraticBezierTo(100, 113, 104, 109),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = _skinShadow,
    );
  }

  void _paintMouth(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF7A2E2E);
    switch (face.mouth) {
      case 1: // seria
        canvas.drawLine(const Offset(89, 124), const Offset(111, 124), paint);
      case 2: // grinta
        canvas.drawPath(
          Path()
            ..moveTo(87, 127)
            ..quadraticBezierTo(100, 119, 113, 127),
          paint,
        );
      default: // sorriso
        canvas.drawPath(
          Path()
            ..moveTo(86, 121)
            ..quadraticBezierTo(100, 134, 114, 121),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(90, 122.5)
            ..quadraticBezierTo(100, 129, 110, 122.5)
            ..close(),
          Paint()..color = Colors.white,
        );
    }
  }

  void _paintBeard(Canvas canvas, Path head) {
    if (face.beard == 0) return;
    final color = _hair;
    Path lowerFace({double extra = 0}) => Path()
      ..moveTo(52, 98)
      ..cubicTo(52, 126, 74, 152 + extra, 100, 152 + extra)
      ..cubicTo(126, 152 + extra, 148, 126, 148, 98)
      ..cubicTo(140, 108, 122, 115, 100, 115)
      ..cubicTo(78, 115, 60, 108, 52, 98)
      ..close();
    final mustache = Path()
      ..moveTo(85, 117)
      ..quadraticBezierTo(100, 108, 115, 117)
      ..quadraticBezierTo(100, 121, 85, 117)
      ..close();
    final fill = Paint();
    switch (face.beard) {
      case 1: // incolta
        canvas.save();
        canvas.clipPath(head);
        canvas.drawPath(
          lowerFace(),
          fill..color = color.withValues(alpha: .32),
        );
        canvas.restore();
      case 2: // corta
        canvas.save();
        canvas.clipPath(head);
        canvas.drawPath(lowerFace(), fill..color = color.withValues(alpha: .8));
        canvas.restore();
        canvas.drawPath(mustache, fill..color = color.withValues(alpha: .8));
      case 3: // piena
        canvas.drawPath(lowerFace(extra: 8), fill..color = color);
        canvas.drawPath(mustache, fill..color = color);
      case 4: // pizzetto
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(100, 138),
            width: 22,
            height: 18,
          ),
          fill..color = color,
        );
        canvas.drawPath(mustache, fill..color = color);
      case 5: // baffi
        canvas.drawPath(mustache, fill..color = color);
    }
    // Spazio pulito attorno alla bocca.
    if (face.beard == 2 || face.beard == 3) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(100, 124), width: 30, height: 14),
        fill..color = _skin,
      );
    }
  }

  void _paintAccessory(Canvas canvas) {
    switch (face.accessory) {
      case 1: // fascia
        canvas.save();
        canvas.clipPath(_headPath().shift(Offset.zero));
        canvas.drawRect(
          const Rect.fromLTRB(40, 58, 160, 70),
          Paint()..color = MilanacColors.red,
        );
        canvas.drawRect(
          const Rect.fromLTRB(40, 63, 160, 65),
          Paint()..color = Colors.white.withValues(alpha: .8),
        );
        canvas.restore();
      case 2: // occhiali
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = const Color(0xFF1E1E22);
        canvas.drawCircle(const Offset(80, 93), 13, paint);
        canvas.drawCircle(const Offset(120, 93), 13, paint);
        canvas.drawLine(const Offset(93, 92), const Offset(107, 92), paint);
        canvas.drawLine(const Offset(67, 90), const Offset(54, 88), paint);
        canvas.drawLine(const Offset(133, 90), const Offset(146, 88), paint);
        canvas.drawCircle(
          const Offset(80, 93),
          13,
          Paint()..color = Colors.white.withValues(alpha: .12),
        );
        canvas.drawCircle(
          const Offset(120, 93),
          13,
          Paint()..color = Colors.white.withValues(alpha: .12),
        );
      case 3: // orecchino
        canvas.drawCircle(
          const Offset(150, 108),
          3.2,
          Paint()..color = MilanacColors.gold,
        );
      case 4: // cerotto
        canvas.save();
        canvas.translate(128, 112);
        canvas.rotate(-.5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 18, height: 8),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFFE8C9A0),
        );
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: 7, height: 5),
          Paint()..color = const Color(0xFFD9B58C),
        );
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter old) =>
      old.face != face || old.crop != crop || old.background != background;
}
