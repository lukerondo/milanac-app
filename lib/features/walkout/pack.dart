import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../carta/card_colors.dart';

/// La bustina da aprire, come i pacchetti FUT: nero oro con le strisce rossonere, lo
/// stemma, il nome e i bordi sigillati. Disegnata a 220×330 e scalata alla larghezza
/// disponibile; si strappa lungo la linea tratteggiata in alto ([PackTearClipper]).
class PackArt extends StatelessWidget {
  const PackArt({
    super.key,
    required this.name,
    this.shine,
    this.foilOnly = false,
  });

  /// Nome del pacchetto sotto lo stemma (SPECIALE, POTENZIAMENTO, BENVENUTO).
  final String name;

  /// Riflesso sulla stagnola: da 0 a 1 attraversa la bustina; null = fermo.
  final double? shine;

  /// Solo la stagnola, senza scritte né stemma (la linguetta che si stacca).
  final bool foilOnly;

  static const width = 220.0, height = 330.0;

  /// Altezza della linea di strappo (frazione dell'altezza).
  static const seam = .16;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: width / height,
    child: FittedBox(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _FoilPainter(shine: shine),
          child: foilOnly
              ? null
              : Stack(
                  children: [
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 62,
                      child: Column(
                        children: [
                          Text(
                            'MILANAC',
                            style: TextStyle(
                              fontFamily: sportFont,
                              fontSize: 28,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 6,
                              color: CardColors.goldText,
                            ),
                          ),
                          Text(
                            'PRO CLUB',
                            style: TextStyle(
                              fontFamily: sportFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 5,
                              color: MilanacColors.ivoryMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 122,
                      child: Center(
                        child: Image.asset(
                          'assets/images/stemma_256.png',
                          height: 100,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 238,
                      child: Column(
                        children: [
                          const Text(
                            'PACCHETTO',
                            style: TextStyle(
                              fontFamily: bodyFont,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                              color: MilanacColors.ivoryMuted,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              name,
                              maxLines: 1,
                              style: const TextStyle(
                                fontFamily: sportFont,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                                color: CardColors.goldText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '1 CARTA',
                            style: TextStyle(
                              fontFamily: bodyFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 3,
                              color: CardColors.neroOroInfo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

/// Stagnola della bustina: fondo nero oro, strisce rossonere, alone dietro lo stemma,
/// fasce sigillate in alto e in basso, linea di strappo con le tacche e riflesso.
class _FoilPainter extends CustomPainter {
  const _FoilPainter({this.shine});
  final double? shine;

  /// Contorno con i bordi seghettati della bustina, in alto e in basso.
  static Path outline(Size size) {
    const teeth = 22, depth = 5.0;
    final w = size.width, h = size.height, tw = w / teeth;
    final path = Path()..moveTo(0, depth);
    for (var i = 0; i < teeth; i++) {
      path
        ..lineTo(i * tw + tw / 2, 0)
        ..lineTo((i + 1) * tw, depth);
    }
    path.lineTo(w, h - depth);
    for (var i = teeth; i > 0; i--) {
      path
        ..lineTo(i * tw - tw / 2, h)
        ..lineTo((i - 1) * tw, h - depth);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = outline(size);
    canvas
      ..save()
      ..clipPath(shape);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-.4, -1),
          end: Alignment(.4, 1),
          colors: [CardColors.neroOroLight, MilanacColors.black],
        ).createShader(rect),
    );
    // Strisce rossonere verticali che sfumano verso il basso.
    final stripes = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          MilanacColors.kitRed.withValues(alpha: .3),
          MilanacColors.kitRed.withValues(alpha: .04),
        ],
      ).createShader(rect);
    for (var x = 12.0; x < size.width; x += 36) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 18, size.height), stripes);
    }
    // Alone d'oro dietro lo stemma e due filetti a V, come sulle bustine FUT.
    final crest = Offset(size.width / 2, 172);
    final halo = Rect.fromCircle(center: crest, radius: 92);
    canvas.drawCircle(
      crest,
      92,
      Paint()
        ..shader = RadialGradient(
          colors: [
            CardColors.metalWarm.withValues(alpha: .32),
            CardColors.metalWarm.withValues(alpha: 0),
          ],
        ).createShader(halo),
    );
    final vee = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = CardColors.metal.withValues(alpha: .55);
    canvas
      ..drawPath(
        Path()
          ..moveTo(10, 108)
          ..lineTo(size.width / 2, 232)
          ..lineTo(size.width - 10, 108),
        vee,
      )
      ..drawPath(
        Path()
          ..moveTo(10, 120)
          ..lineTo(size.width / 2, 244)
          ..lineTo(size.width - 10, 120),
        vee..color = CardColors.metal.withValues(alpha: .25),
      );
    _seal(canvas, Rect.fromLTRB(0, 0, size.width, 18));
    _seal(canvas, Rect.fromLTRB(0, size.height - 18, size.width, size.height));
    // Linea di strappo tratteggiata, con le tacche ai lati.
    final y = size.height * PackArt.seam;
    final dash = Paint()
      ..color = CardColors.metalWarm.withValues(alpha: .75)
      ..strokeWidth = 1.2;
    for (var x = 12.0; x < size.width - 14; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(x + 5, y), dash);
    }
    final notch = Paint()..color = MilanacColors.black;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, y - 4)
          ..lineTo(6, y)
          ..lineTo(0, y + 4)
          ..close(),
        notch,
      )
      ..drawPath(
        Path()
          ..moveTo(size.width, y - 4)
          ..lineTo(size.width - 6, y)
          ..lineTo(size.width, y + 4)
          ..close(),
        notch,
      );
    final s = shine;
    if (s != null) {
      final c = -1.8 + 3.6 * s;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(c - .7, -1),
            end: Alignment(c + .7, 1),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: .17),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    canvas
      ..restore()
      ..drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = CardColors.gold,
      );
  }

  /// Fascia sigillata: oro con le righe in rilievo.
  void _seal(Canvas canvas, Rect r) {
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CardColors.metalDeep,
            CardColors.metalWarm,
            CardColors.metalDeep,
          ],
        ).createShader(r),
    );
    final ridge = Paint()
      ..color = Colors.black.withValues(alpha: .28)
      ..strokeWidth = 1;
    for (var x = r.left + 1.5; x < r.right; x += 3.5) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), ridge);
    }
  }

  @override
  bool shouldRepaint(_FoilPainter old) => old.shine != shine;
}

/// Taglia la bustina lungo lo strappo: la linguetta in alto ([top]) o il resto. Lo
/// strappo è irregolare e uguale per le due parti, così combaciano.
class PackTearClipper extends CustomClipper<Path> {
  const PackTearClipper({required this.top});
  final bool top;

  @override
  Path getClip(Size size) {
    const steps = 16;
    final y = size.height * PackArt.seam;
    final jag = 2.5 * size.height / PackArt.height;
    final edge = [
      for (var i = 0; i <= steps; i++)
        Offset(size.width * i / steps, y + (i.isEven ? -jag : jag)),
    ];
    // Margini larghi: l'ombra e il bordo non vanno tagliati.
    final far = size.longestSide;
    final path = Path()..moveTo(-far, top ? -far : size.height + far);
    path.lineTo(-far, edge.first.dy);
    for (final p in edge) {
      path.lineTo(p.dx, p.dy);
    }
    return path
      ..lineTo(size.width + far, edge.last.dy)
      ..lineTo(size.width + far, top ? -far : size.height + far)
      ..close();
  }

  @override
  bool shouldReclip(PackTearClipper old) => old.top != top;
}

/// Il pacchetto nelle sue fasi: entra dall'alto ([entry]), fluttua ([float]: fase di un
/// giro), si apre un po' tirandolo in su ([pull]), trema ([shake]) e si strappa
/// ([burst]: la linguetta vola via e il resto cade). Dallo strappo esce la luce del
/// colore della carta ([color]): è il primo indizio della rarità.
class OpeningPack extends StatelessWidget {
  const OpeningPack({
    super.key,
    required this.name,
    required this.color,
    this.entry = 1,
    this.float = 0,
    this.pull = 0,
    this.shake = 0,
    this.burst = 0,
    this.shine,
  });
  final String name;
  final Color color;
  final double entry, float, pull, shake, burst;
  final double? shine;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth, h = w * PackArt.height / PackArt.width;
      final seamY = h * PackArt.seam;
      final bob = math.sin(float * 2 * math.pi);
      final quake = shake == 0
          ? 0.0
          : math.sin(shake * 38) * (1.5 + 8 * shake) * (1 - burst);
      final fly = Curves.easeIn.transform(burst);
      final leak = (math.max(pull, shake) * (1 - burst)).clamp(0.0, 1.0);
      final drop = Curves.easeOutBack.transform(entry.clamp(0.0, 1.0));
      return Transform.translate(
        offset: Offset(quake, (1 - drop) * -h * .9 + bob * 6),
        child: Transform.rotate(
          angle: bob * .025 + quake * .004,
          child: Opacity(
            opacity: (entry / .25).clamp(0.0, 1.0),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Il corpo della bustina cade e sparisce.
                  Transform.translate(
                    offset: Offset(0, fly * h * 1.1),
                    child: Opacity(
                      opacity: 1 - fly,
                      child: ClipPath(
                        clipper: const PackTearClipper(top: false),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: .18 + .4 * leak),
                                blurRadius: 40,
                              ),
                            ],
                          ),
                          child: PackArt(name: name, shine: shine),
                        ),
                      ),
                    ),
                  ),
                  if (leak > 0)
                    Positioned(
                      left: -w * .5,
                      right: -w * .5,
                      top: seamY - h * .5,
                      height: h,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: SeamLeakPainter(leak: leak, color: color),
                        ),
                      ),
                    ),
                  // La linguetta si stacca dalla tacca a destra tirando, poi vola
                  // via ruotando.
                  Transform(
                    origin: Offset(0, seamY),
                    transform: Matrix4.translationValues(
                      -w * .35 * fly,
                      -seamY * .25 * pull - h * 1.3 * fly,
                      0,
                    )..rotateZ(-.1 * pull - 1.2 * fly),
                    child: Opacity(
                      opacity: 1 - fly,
                      child: ClipPath(
                        clipper: const PackTearClipper(top: true),
                        child: PackArt(
                          name: name,
                          shine: shine,
                          foilOnly: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// La luce che esce dallo strappo: una riga accesa lungo la linea e i fasci a ventaglio,
/// sempre più forti con [leak] (da 0 a 1). Il centro del disegno è il centro della linea.
class SeamLeakPainter extends CustomPainter {
  const SeamLeakPainter({required this.leak, required this.color});
  final double leak;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (leak <= 0) return;
    final c = size.center(Offset.zero);
    final half =
        size.width / 4; // metà della bustina (il disegno è largo il doppio)
    final reach = size.height * .5 * (.3 + .7 * leak);
    final rays = Rect.fromCircle(center: c, radius: reach);
    for (var i = 0; i < 9; i++) {
      final x = (i - 4) / 4; // da -1 a 1 lungo lo strappo
      for (final dir in const [-1.0, 1.0]) {
        // Più lunghi verso l'alto, dove la bustina si apre.
        final length = reach * (dir < 0 ? 1 : .55) * (1 - .35 * x.abs());
        final start = Offset(c.dx + x * half * .9, c.dy);
        final end = Offset(c.dx + x * half * 1.9, c.dy + dir * length);
        canvas.drawPath(
          Path()
            ..moveTo(start.dx - 2, start.dy)
            ..lineTo(end.dx - 9, end.dy)
            ..lineTo(end.dx + 9, end.dy)
            ..lineTo(start.dx + 2, start.dy)
            ..close(),
          Paint()
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: .7 * leak),
                color.withValues(alpha: 0),
              ],
            ).createShader(rays),
        );
      }
    }
    final line = Rect.fromCenter(
      center: c,
      width: half * 2 * (.7 + .3 * leak),
      height: 2 + 5 * leak,
    );
    canvas
      ..drawRect(
        line.inflate(6 * leak),
        Paint()
          ..color = color.withValues(alpha: .8 * leak)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 12 * leak),
      )
      ..drawRect(
        line,
        Paint()
          ..color = Colors.white.withValues(alpha: .9 * leak)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 + 3 * leak),
      );
  }

  @override
  bool shouldRepaint(SeamLeakPainter old) =>
      old.leak != leak || old.color != color;
}
