import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Caricamento del club al posto della rotellina: un arco d'oro che gira (con il pallone
/// al centro nelle misure grandi). Con [value] (da 0 a 1) mostra quanto manca, fermo.
/// [color] per i pulsanti colorati (di solito il colore del testo del pulsante).
class GoldLoader extends StatefulWidget {
  const GoldLoader({super.key, this.size = 36, this.color, this.value});
  final double size;
  final Color? color;
  final double? value;

  @override
  State<GoldLoader> createState() => _GoldLoaderState();
}

class _GoldLoaderState extends State<GoldLoader>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) _spin.repeat();
  }

  @override
  void didUpdateWidget(GoldLoader old) {
    super.didUpdateWidget(old);
    if (widget.value == null && !_spin.isAnimating) {
      _spin.repeat();
    } else if (widget.value != null) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.pal.accentText;
    final size = widget.size;
    return Semantics(
      label: 'Caricamento',
      value: widget.value == null ? null : '${(widget.value! * 100).round()}%',
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, child) => CustomPaint(
            painter: _ArcPainter(
              turn: _spin.value,
              value: widget.value,
              color: color,
            ),
            child: child,
          ),
          // Il pallone al centro solo dove c'è spazio (non nei pulsanti).
          child: size >= 28
              ? Center(
                  child: Icon(
                    Icons.sports_soccer_rounded,
                    size: size * .42,
                    color: color.withValues(alpha: .85),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// La pista sottile e l'arco d'oro con la testa più luminosa.
class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.turn,
    required this.value,
    required this.color,
  });
  final double turn;
  final double? value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(2.0, size.shortestSide / 12);
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: .18),
    );
    final v = value;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (v != null) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * v.clamp(0.0, 1.0),
        false,
        arc..color = color,
      );
      return;
    }
    // Un arco di tre quarti di giro che sfuma verso la coda, e gira.
    final start = turn * 2 * math.pi;
    arc.shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [color.withValues(alpha: 0), color],
      stops: const [0, .75],
      transform: GradientRotation(start),
    ).createShader(rect);
    canvas.drawArc(rect, start, 2 * math.pi * .75, false, arc);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.turn != turn || old.value != value || old.color != color;
}

/// Barra di caricamento d'oro (al posto di quella lineare): una luce che scorre.
class GoldBar extends StatefulWidget {
  const GoldBar({super.key, this.height = 3});
  final double height;

  @override
  State<GoldBar> createState() => _GoldBarState();
}

class _GoldBarState extends State<GoldBar> with SingleTickerProviderStateMixin {
  late final _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.pal.accentText;
    return Semantics(
      label: 'Caricamento',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _run,
            builder: (context, _) {
              final x = -1.6 + 3.2 * Curves.easeInOut.transform(_run.value);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .18),
                  gradient: LinearGradient(
                    begin: Alignment(x - .6, 0),
                    end: Alignment(x + .6, 0),
                    colors: [
                      color.withValues(alpha: .18),
                      color,
                      color.withValues(alpha: .18),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
