import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Un'esplosione di scintille: parte da [at] [seconds] secondi fa (negativo = non
/// ancora). [at] e [launch] sono frazioni del disegno (0,0 in alto a sinistra, 1,1 in
/// basso a destra). Con [launch] è un fuoco d'artificio: prima sale il razzo da lì.
@immutable
class Burst {
  const Burst({
    required this.at,
    required this.seconds,
    required this.color,
    this.count = 48,
    this.speed = 520,
    this.seed = 1,
    this.ring = false,
    this.launch,
  });
  final Offset at;
  final double seconds;
  final Color color;
  final int count;

  /// Velocità iniziale delle scintille più veloci (pixel al secondo).
  final double speed;
  final int seed;

  /// Onda d'urto: un anello di luce che si allarga.
  final bool ring;
  final Offset? launch;

  @override
  bool operator ==(Object other) =>
      other is Burst &&
      other.at == at &&
      other.seconds == seconds &&
      other.color == color &&
      other.count == count &&
      other.speed == speed &&
      other.seed == seed &&
      other.ring == ring &&
      other.launch == launch;

  @override
  int get hashCode =>
      Object.hash(at, seconds, color, count, speed, seed, ring, launch);
}

/// Scintille, onde di luce e fuochi d'artificio dell'apertura del pacchetto.
class BurstPainter extends CustomPainter {
  const BurstPainter(this.bursts);
  final List<Burst> bursts;

  /// Quanto durano le scintille, la salita del razzo e l'onda (secondi).
  static const life = 1.4, rocket = .45, wave = .7;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bursts) {
      final s = b.seconds;
      final center = Offset(b.at.dx * size.width, b.at.dy * size.height);
      final launch = b.launch;
      if (launch != null && s < 0 && s > -rocket) {
        _rocket(
          canvas,
          Offset(launch.dx * size.width, launch.dy * size.height),
          center,
          1 + s / rocket,
          b.color,
        );
      }
      if (s < 0 || s > life) continue;
      if (b.ring && s < wave) {
        final k = s / wave;
        canvas.drawCircle(
          center,
          size.longestSide * .7 * Curves.easeOut.transform(k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 + 14 * (1 - k)
            ..color = Color.lerp(
              Colors.white,
              b.color,
              k,
            )!.withValues(alpha: .75 * (1 - k))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      final fade = 1 - s / life;
      final rnd = math.Random(b.seed);
      final spark = Paint()..strokeCap = StrokeCap.round;
      for (var i = 0; i < b.count; i++) {
        final angle = rnd.nextDouble() * 2 * math.pi;
        final speed = b.speed * (.3 + .7 * rnd.nextDouble());
        final width = 1.2 + 2.2 * rnd.nextDouble();
        final white = rnd.nextDouble() < .3;
        // L'aria le frena e piano piano cadono.
        Offset at(double t) {
          final d = speed * (1 - math.exp(-2.4 * t)) / 2.4;
          return center +
              Offset(math.cos(angle) * d, math.sin(angle) * d + 160 * t * t);
        }

        spark
          ..color = (white ? Colors.white : b.color).withValues(
            alpha: fade * fade,
          )
          ..strokeWidth = width * (.5 + .5 * fade);
        canvas.drawLine(at(math.max(0, s - .06)), at(s), spark);
      }
    }
  }

  /// Il razzo che sale verso il punto dello scoppio ([p] da 0 a 1), con la scia.
  void _rocket(Canvas canvas, Offset from, Offset to, double p, Color color) {
    final head = Offset.lerp(from, to, Curves.easeOutCubic.transform(p))!;
    final tail = Offset.lerp(
      from,
      to,
      Curves.easeOutCubic.transform(math.max(0, p - .3)),
    )!;
    if ((head - tail).distance < 1) return;
    canvas
      ..drawLine(
        tail,
        head,
        Paint()
          ..shader = ui.Gradient.linear(tail, head, [
            color.withValues(alpha: 0),
            color.withValues(alpha: .9),
          ])
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(head, 2.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(BurstPainter old) => !listEquals(old.bursts, bursts);
}

/// Sfondo del walkout: righe verticali d'oro, l'alone dietro la carta, i fasci di luce
/// che ruotano con le scintille e, in basso, San Siro: tribuna, travi rosse del tetto,
/// torri a rampa, fari e flash del pubblico.
class WalkoutBackdropPainter extends CustomPainter {
  const WalkoutBackdropPainter({
    required this.color,
    required this.glow,
    required this.beams,
    required this.spin,
    required this.twinkle,
    required this.lights,
  });
  final Color color;

  /// Intensità dell'alone e opacità dei fasci (da 0 a 1); rotazione dei fasci (radianti).
  final double glow, beams, spin;

  /// Fase delle scintille e dei flash del pubblico.
  final double twinkle;

  /// Luci dello stadio: 0 spente (pacchetto chiuso), 1 accese.
  final double lights;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = Paint()
      ..color = MilanacColors.gold.withValues(alpha: .09)
      ..strokeWidth = 1.5;
    for (var x = .75; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), lines);
    }
    final glowCenter = Offset(size.width / 2, size.height * .45);
    final glowRadius = size.width * .8;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .34 * glow),
            color.withValues(alpha: .12 * glow),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );
    if (beams > 0) _beams(canvas, size);
    _stadium(canvas, size);
  }

  /// Fasci di luce da stadio che ruotano, con le scintille.
  void _beams(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .62);
    final radius = size.longestSide;
    const count = 14;
    for (var i = 0; i < count; i++) {
      final a = spin + i * 2 * math.pi / count;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(a - .05) * radius,
          center.dy + math.sin(a - .05) * radius,
        )
        ..lineTo(
          center.dx + math.cos(a + .05) * radius,
          center.dy + math.sin(a + .05) * radius,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (i.isEven ? .28 : .14) * glow * beams),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    final rnd = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final on = (math.sin(twinkle + i) + 1) / 2;
      canvas.drawCircle(
        Offset(x, y),
        1 + rnd.nextDouble() * 1.5,
        Paint()..color = color.withValues(alpha: .6 * on * glow * beams),
      );
    }
  }

  /// San Siro di notte visto dal campo: la tribuna di fronte con il tetto a travi rosse,
  /// le torri a rampa, i fari che si accendono e i flash del pubblico.
  void _stadium(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final roof = h * .86, eaves = h * .878;
    if (lights > 0) {
      // Il chiarore dei fari sopra il tetto.
      final sky = Rect.fromLTRB(0, roof - h * .14, w, roof);
      canvas.drawRect(
        sky,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: .26 * lights),
              color.withValues(alpha: 0),
            ],
          ).createShader(sky),
      );
    }
    canvas.drawRect(
      Rect.fromLTRB(0, roof, w, h),
      Paint()..color = MilanacColors.ink,
    );
    final tiers = Paint()
      ..color = MilanacColors.gold.withValues(alpha: .06)
      ..strokeWidth = 1;
    for (var y = eaves + 6; y < h; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(w, y), tiers);
    }
    // Le torri cilindriche con la rampa a spirale, più alte della tribuna.
    for (final x in const [.06, .32, .68, .94]) {
      final tower = Rect.fromLTRB(
        w * x - w * .035,
        roof - h * .025,
        w * x + w * .035,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          tower,
          topLeft: Radius.circular(w * .012),
          topRight: Radius.circular(w * .012),
        ),
        Paint()..color = MilanacColors.surface,
      );
      final ramp = Paint()
        ..color = MilanacColors.ivory.withValues(alpha: .07)
        ..strokeWidth = 1;
      for (var y = tower.top + 6; y < h; y += 8) {
        canvas.drawLine(
          Offset(tower.left, y + 5),
          Offset(tower.right, y),
          ramp,
        );
      }
    }
    // Il tetto: le travi rosse a traliccio da una torre all'altra.
    final truss = Paint()
      ..color = MilanacColors.kitRed.withValues(alpha: .6)
      ..strokeWidth = 1.4;
    for (var x = 0.0; x < w; x += 16) {
      canvas
        ..drawLine(Offset(x, roof), Offset(x + 8, eaves), truss)
        ..drawLine(Offset(x + 8, eaves), Offset(x + 16, roof), truss);
    }
    canvas
      ..drawLine(Offset(0, roof), Offset(w, roof), truss..strokeWidth = 2)
      ..drawLine(Offset(0, eaves), Offset(w, eaves), truss);
    if (lights <= 0) return;
    final halo = Paint()
      ..color = color.withValues(alpha: .5 * lights)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final lamp = Paint()..color = MilanacColors.ivory.withValues(alpha: lights);
    for (var x = w * .05; x < w; x += w * .1) {
      canvas
        ..drawCircle(Offset(x, roof - 2), 6, halo)
        ..drawCircle(Offset(x, roof - 2), 1.8, lamp);
    }
    // Flash delle foto dal pubblico, qua e là.
    final rnd = math.Random(3);
    final flash = Paint();
    for (var i = 0; i < 36; i++) {
      final at = Offset(
        rnd.nextDouble() * w,
        eaves + 8 + rnd.nextDouble() * (h - eaves - 16),
      );
      final on = math.sin(twinkle * .6 + i * 7.3);
      if (on > .93) {
        canvas.drawCircle(
          at,
          1.4,
          flash
            ..color = Colors.white.withValues(alpha: lights * (on - .93) / .07),
        );
      }
    }
  }

  @override
  bool shouldRepaint(WalkoutBackdropPainter old) =>
      old.color != color ||
      old.glow != glow ||
      old.beams != beams ||
      old.spin != spin ||
      old.twinkle != twinkle ||
      old.lights != lights;
}
