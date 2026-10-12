import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/card_colors.dart';
import '../carta/card_stats.dart';
import '../carta/fut_card.dart';
import '../carte/special_cards_repository.dart';
import '../risultati/match.dart';
import '../rosa/member.dart';

/// Apre il walkout come nei pacchetti FUT: luci, bandiera, ruolo, stemma, poi la carta.
/// [previousOverall] valorizzato = "overall aumentato", altrimenti "benvenuto".
/// [caption] è la frase sotto la carta (es. perché è arrivata la carta speciale).
Future<void> showWalkout(
  BuildContext context, {
  required Member member,
  required CardStats stats,
  int? previousOverall,
  CardSpecial? special,
  int bonus = 0,
  String? caption,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, _, _) => WalkoutPage(
      member: member,
      stats: stats,
      previousOverall: previousOverall,
      special: special,
      bonus: bonus,
      caption: caption,
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

/// La frase sotto la carta speciale nel walkout: "Il Direttivo ti ha scelto per il
/// centrocampo della 2ª giornata." (con [name], per la carta di un compagno).
String specialCardCaption(SpecialCard card, {ClubMatch? match, String? name}) {
  if (card.isBlue) {
    final reason =
        card.reason ?? 'Tripletta o tre partite di fila senza subire gol';
    return reason.endsWith('.') ? reason : '$reason.';
  }
  final reparto = switch (card.reparto) {
    'POR' => 'la porta',
    'DIF' => 'la difesa',
    'CEN' => 'il centrocampo',
    'ATT' => "l'attacco",
    _ => 'la squadra',
  };
  final day = match == null
      ? null
      : matchdayOf(match) ?? 'partita con ${match.opponent}';
  final who = name == null ? 'ti ha scelto' : 'ha scelto $name';
  return 'Il Direttivo $who per $reparto${day == null ? '' : ' della $day'}.';
}

class WalkoutPage extends StatefulWidget {
  const WalkoutPage({
    super.key,
    required this.member,
    required this.stats,
    this.previousOverall,
    this.special,
    this.bonus = 0,
    this.caption,
  });
  final Member member;
  final CardStats stats;
  final int? previousOverall;

  /// Carta speciale appena ricevuta (nero/oro o blu elettrico) con il suo bonus.
  final CardSpecial? special;
  final int bonus;

  /// Frase sotto la carta; senza, una frase per l'overall nuovo o il benvenuto.
  final String? caption;

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

  /// Salta alla fine dell'animazione.
  void _skip() {
    _lastStep = 99;
    _c.value = 1;
  }

  /// Tocco: salta alla fine; a fine animazione chiude.
  void _onTap() => _c.isCompleted ? Navigator.of(context).pop() : _skip();

  /// Colore delle luci e del titolo: quello della carta.
  Color get _accent => switch (widget.special) {
    CardSpecial.blu => CardColors.blueRing,
    CardSpecial.neroOro => CardColors.goldText,
    null => switch (tierOf(widget.member.overall)) {
      CardTier.vuota => MilanacColors.ivory,
      final tier => CardColors.tier(tier),
    },
  };

  int? get _up {
    final m = widget.member;
    final before = widget.previousOverall;
    return before != null && m.overall != null ? m.overall! - before : null;
  }

  String get _title => switch (widget.special) {
    CardSpecial.blu => 'BLU ELETTRICO',
    CardSpecial.neroOro => 'CARTA DELLA SETTIMANA',
    null => (_up ?? 0) > 0 ? 'OVERALL +$_up' : 'NUOVO ACQUISTO!',
  };

  String get _caption =>
      widget.caption ??
      ((_up ?? 0) > 0
          ? "L'overall sale a ${widget.member.overall}."
          : 'Benvenuto nel MILANAC Pro Club.');

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return Scaffold(
      backgroundColor: MilanacColors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final end = ((t - _flipEnd) / (1 - _flipEnd)).clamp(0.0, 1.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _BackdropPainter(t: t, color: _accent),
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
                          color: MilanacColors.ivory,
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
                      fontWeight: FontWeight.w700,
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
                // Titolo, carta e frase, come nella tavola del walkout.
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 70, 24, 120),
                    child: Column(
                      children: [
                        Opacity(
                          opacity: t < .06
                              ? t / .06
                              : (t > _flipAt && t < _flipEnd ? .4 : 1),
                          child: Text(
                            t < _flipEnd ? 'MILANAC PRO CLUB' : _title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: sportFont,
                              color: t < _flipEnd
                                  ? MilanacColors.ivoryMuted
                                  : _accent,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Flexible(
                          child: t >= _flipAt
                              ? _flippingCard(t)
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: end,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              _caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                color: MilanacColors.ivoryMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (t < 1)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            foregroundColor: MilanacColors.ivory,
                            backgroundColor: MilanacColors.black.withValues(
                              alpha: .5,
                            ),
                            side: BorderSide(
                              color: MilanacColors.goldLight.withValues(
                                alpha: .6,
                              ),
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontFamily: bodyFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _skip,
                          child: const Text('Salta'),
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      child: t >= 1
                          ? FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                backgroundColor: MilanacColors.gold,
                                foregroundColor: MilanacColors.ink,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: bodyFont,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Continua'),
                            )
                          : const SizedBox.shrink(),
                    ),
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
    return Transform.scale(
      scale: scale,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .0012)
          ..rotateY(front ? a : a - pi),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: .32 * p),
                  blurRadius: 60,
                ),
              ],
            ),
            child: front
                ? FutCard(
                    member: widget.member,
                    special: widget.special,
                    bonus: widget.bonus,
                    glow: false,
                  )
                : const FutCardBack(),
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

/// Sfondo del walkout: righe verticali d'oro, l'alone dietro la carta e, mentre si
/// rivela, i fasci di luce da stadio che ruotano (spariscono quando la carta è girata).
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Righe verticali, come la tavola.
    final lines = Paint()
      ..color = MilanacColors.gold.withValues(alpha: .09)
      ..strokeWidth = 1.5;
    for (var x = .75; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), lines);
    }
    final intensity = (.25 + .75 * t).clamp(0.0, 1.0);
    // Alone dietro la carta.
    final glowCenter = Offset(size.width / 2, size.height * .45);
    final glowRadius = size.width * .8;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .34 * intensity),
            color.withValues(alpha: .12 * intensity),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );
    // Fasci di luce fino a quando la carta è girata.
    final beamsOpacity = t < _flipAt
        ? 1.0
        : (1 - (t - _flipAt) / (_flipEnd - _flipAt)).clamp(0.0, 1.0);
    if (beamsOpacity == 0) return;
    final center = Offset(size.width / 2, size.height * .62);
    final radius = size.longestSide;
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
              color.withValues(
                alpha: (i.isEven ? .28 : .14) * intensity * beamsOpacity,
              ),
              color.withValues(alpha: 0),
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
        Paint()
          ..color = color.withValues(
            alpha: .6 * twinkle * intensity * beamsOpacity,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t || old.color != color;
}
