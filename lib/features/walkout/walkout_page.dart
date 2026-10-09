import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/card_stats.dart';
import '../carta/fut_card.dart';
import '../rosa/member.dart';

/// Apre il walkout come nei pacchetti FUT: luci, bandiera, ruolo, stemma, poi la carta.
/// [previousOverall] valorizzato = "overall aumentato", altrimenti "benvenuto".
Future<void> showWalkout(
  BuildContext context, {
  required Member member,
  required CardStats stats,
  int? previousOverall,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, _, _) => WalkoutPage(
      member: member,
      stats: stats,
      previousOverall: previousOverall,
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class WalkoutPage extends StatefulWidget {
  const WalkoutPage({
    super.key,
    required this.member,
    required this.stats,
    this.previousOverall,
  });
  final Member member;
  final CardStats stats;
  final int? previousOverall;

  static const duration = Duration(milliseconds: 7600);

  @override
  State<WalkoutPage> createState() => _WalkoutPageState();
}

/// Momenti dell'animazione (frazioni della durata totale).
const _flagAt = .14, _positionAt = .31, _crestAt = .48, _flipAt = .65;
const _flipEnd = .80;

class _WalkoutPageState extends State<WalkoutPage>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: WalkoutPage.duration,
  )..addListener(_haptics);
  var _lastStep = -1;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Una vibrazione a ogni rivelazione, più forte quando si gira la carta.
  void _haptics() {
    final step = [
      _flagAt,
      _positionAt,
      _crestAt,
      _flipAt,
      _flipEnd,
    ].lastIndexWhere((t) => _c.value >= t);
    if (step > _lastStep) {
      _lastStep = step;
      step >= 3 ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
    }
  }

  /// Tocco: salta alla fine; a fine animazione chiude.
  void _onTap() {
    if (_c.isCompleted) {
      Navigator.of(context).pop();
    } else {
      _lastStep = 99;
      _c.value = 1;
    }
  }

  Color get _accent => switch (tierOf(widget.member.overall)) {
    CardTier.rossonera => const Color(0xFFE0182F),
    CardTier.oro => const Color(0xFFF3D27A),
    CardTier.argento => const Color(0xFFDDE2EA),
    CardTier.bronzo => const Color(0xFFD9A273),
    CardTier.vuota => Colors.white,
  };

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final up = widget.previousOverall != null && m.overall != null
        ? m.overall! - widget.previousOverall!
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _BeamsPainter(t: t, color: _accent),
                ),
                // Rivelazioni una alla volta, al centro.
                _Reveal(
                  t: t,
                  from: _flagAt,
                  to: _positionAt,
                  child: m.nationality == null
                      ? const Icon(
                          Icons.public_rounded,
                          size: 120,
                          color: Colors.white,
                        )
                      : Text(
                          flagEmoji(m.nationality!),
                          style: const TextStyle(fontSize: 120),
                        ),
                ),
                _Reveal(
                  t: t,
                  from: _positionAt,
                  to: _crestAt,
                  child: Text(
                    m.fieldPosition ?? '??',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                      color: _accent,
                      letterSpacing: 4,
                      shadows: [Shadow(color: _accent, blurRadius: 30)],
                    ),
                  ),
                ),
                _Reveal(
                  t: t,
                  from: _crestAt,
                  to: _flipAt,
                  child: Image.asset(
                    'assets/images/stemma_256.png',
                    height: 170,
                  ),
                ),
                if (t >= _flipAt) _flippingCard(t),
                // Titolo in alto.
                Positioned(
                  top: 70,
                  left: 24,
                  right: 24,
                  child: Opacity(
                    opacity: t < .06
                        ? t / .06
                        : (t > _flipAt && t < _flipEnd ? .4 : 1),
                    child: Text(
                      t < _flipEnd
                          ? 'MILANAC PRO CLUB'
                          : up != null && up > 0
                          ? 'OVERALL +$up'
                          : 'NUOVO ACQUISTO!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: sportFont,
                        color: t < _flipEnd ? Colors.white70 : _accent,
                        fontSize: t < _flipEnd ? 16 : 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 24,
                  right: 24,
                  child: t >= 1
                      ? Column(
                          children: [
                            Text(
                              m.displayName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: sportFont,
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Continua'),
                            ),
                          ],
                        )
                      : const Text(
                          'Tocca per saltare',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white30, fontSize: 12),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _flippingCard(double t) {
    final p = Curves.easeInOutCubic.transform(
      ((t - _flipAt) / (_flipEnd - _flipAt)).clamp(0, 1),
    );
    // Due giri completi: si ferma di fronte. Tra 90° e 270° si vede il retro.
    final a = (p * 4 * pi) % (2 * pi);
    final front = a < pi / 2 || a > 3 * pi / 2;
    final scale = .55 + .45 * Curves.easeOutBack.transform(p);
    return Center(
      child: Transform.scale(
        scale: scale,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY(front ? a : a - pi),
          child: SizedBox(
            width: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: .5 * p),
                    blurRadius: 60,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: front
                  ? FutCard(member: widget.member, stats: widget.stats)
                  : const _CardBack(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Elemento che entra ingrandendosi e poi svanisce, tra [from] e [to].
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.t,
    required this.from,
    required this.to,
    required this.child,
  });
  final double t, from, to;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (t < from || t > to) return const SizedBox.shrink();
    final p = (t - from) / (to - from);
    final opacity = p < .25 ? p / .25 : (p > .8 ? (1 - p) / .2 : 1.0);
    final scale = .6 + .5 * Curves.easeOutBack.transform(min(1, p / .35));
    return Center(
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.scale(scale: scale, child: child),
      ),
    );
  }
}

/// Retro della carta: rosso scuro con lo stemma.
class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 300 / 428,
    child: ClipPath(
      clipper: _CardClipper(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8E0B20), Color(0xFF0B0B0D)],
          ),
        ),
        child: Center(
          child: Image.asset('assets/images/stemma_256.png', width: 110),
        ),
      ),
    ),
  );
}

class _CardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => cardShape(size);
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Fasci di luce da stadio che ruotano dal basso, più intensi verso la fine.
class _BeamsPainter extends CustomPainter {
  _BeamsPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .62);
    final radius = size.longestSide;
    final intensity = (.25 + .75 * t).clamp(0.0, 1.0);
    // Alone centrale.
    canvas.drawCircle(
      center,
      radius * .5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .35 * intensity),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius * .5)),
    );
    // Raggi.
    const beams = 14;
    final rotation = t * pi * .9;
    for (var i = 0; i < beams; i++) {
      final a = rotation + i * 2 * pi / beams;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + cos(a - .05) * radius,
          center.dy + sin(a - .05) * radius,
        )
        ..lineTo(
          center.dx + cos(a + .05) * radius,
          center.dy + sin(a + .05) * radius,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (i.isEven ? .28 : .14) * intensity),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    // Scintille.
    final rnd = Random(7);
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final twinkle = (sin(t * 40 + i) + 1) / 2;
      canvas.drawCircle(
        Offset(x, y),
        1 + rnd.nextDouble() * 1.5,
        Paint()..color = color.withValues(alpha: .6 * twinkle * intensity),
      );
    }
  }

  @override
  bool shouldRepaint(_BeamsPainter old) => old.t != t || old.color != color;
}
