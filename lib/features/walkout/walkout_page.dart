import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/card_colors.dart';
import '../carta/card_stats.dart';
import '../carta/fut_card.dart';
import '../carta/live_card.dart';
import '../carte/special_cards_repository.dart';
import '../risultati/match.dart';
import '../rosa/member.dart';
import 'pack.dart';
import 'walkout_fx.dart';

/// Apre il pacchetto come in FUT: la bustina si apre con un tocco (o tirandola in su),
/// esplode la luce del colore della carta, poi il walkout (bandiera, ruolo, stemma) e la
/// carta che gira. [previousOverall] valorizzato = "overall aumentato", altrimenti
/// "benvenuto". [caption] è la frase sotto la carta (es. perché è arrivata la speciale).
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

  /// Dall'apertura del pacchetto alla carta ferma.
  static const duration = Duration(milliseconds: 8000);

  @override
  State<WalkoutPage> createState() => _WalkoutPageState();
}

/// Momenti dell'apertura (frazioni della durata): il pacchetto trema e si strappa, poi
/// bandiera, ruolo, stemma, la carta che gira e l'overall che sale.
const _tearAt = .06, _flagAt = .2, _positionAt = .35, _crestAt = .5;
const _flipAt = .65, _flipEnd = .8, _countEnd = .9;

/// Quanto tirare in su il pacchetto perché si apra lasciandolo (frazione del tiro).
const _pullToOpen = .5;

class _WalkoutPageState extends State<WalkoutPage>
    with TickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: WalkoutPage.duration,
  )..addListener(_onTick);

  /// Il pacchetto che arriva, che fluttua in attesa e quanto è stato tirato in su.
  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final _pull = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  var _opened = false;
  var _beat = 0;
  var _counted = 0;

  /// Vibrazioni: colpetti mentre il pacchetto trema, forte allo strappo, una per ogni
  /// rivelazione e la più forte quando la carta si ferma.
  static const _beats = [
    (.018, Haptics.tap),
    (.034, Haptics.tap),
    (.048, Haptics.tap),
    (_tearAt, Haptics.heavy),
    (_flagAt, Haptics.medium),
    (_positionAt, Haptics.medium),
    (_crestAt, Haptics.medium),
    (_flipAt, Haptics.light),
    (_flipEnd, Haptics.heavy),
  ];

  @override
  void initState() {
    super.initState();
    Haptics.light();
    _enter.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Con "riduci animazioni" del telefono il pacchetto aspetta fermo.
      final still =
          mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
      if (mounted && !_opened && !still) _idle.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _enter.dispose();
    _idle.dispose();
    _pull.dispose();
    super.dispose();
  }

  double get _seconds => WalkoutPage.duration.inMilliseconds / 1000;

  /// Vibrazioni a tempo e un tic per ogni punto che l'overall guadagna.
  void _onTick() {
    while (_beat < _beats.length && _c.value >= _beats[_beat].$1) {
      _beats[_beat++].$2();
    }
    final counted = _counting(_c.value);
    if (counted != _counted) {
      _counted = counted;
      Haptics.tap();
    }
  }

  void _open() {
    if (_opened) return;
    setState(() => _opened = true);
    _idle.stop();
    _enter.value = 1;
    _c.forward();
  }

  /// Salta alla carta ferma (anche dal pacchetto chiuso), senza la raffica di vibrazioni.
  void _skip() {
    setState(() => _opened = true);
    _idle.stop();
    _enter.value = 1;
    _beat = _beats.length;
    _counted = _countTo;
    _c.value = 1;
  }

  /// Tocco: apre il pacchetto, poi salta alla fine. A carta ferma non chiude (la carta
  /// si inclina seguendo il dito): si esce con Continua.
  void _onTap() {
    if (!_opened) {
      _open();
    } else if (!_c.isCompleted) {
      _skip();
    }
  }

  void _onPull(DragUpdateDetails d) {
    final before = _pull.value;
    _pull.value = (before - d.delta.dy / 180).clamp(0.0, 1.0);
    // Un tic quando basta lasciarlo per aprirlo.
    if (before < _pullToOpen && _pull.value >= _pullToOpen) {
      Haptics.tap();
    }
  }

  void _onPullEnd(DragEndDetails d) {
    if (_pull.value >= _pullToOpen || (d.primaryVelocity ?? 0) < -800) {
      _open();
    } else {
      _pull.animateTo(0, curve: Curves.easeOut);
    }
  }

  /// Colore delle luci e del titolo: quello della carta.
  Color get _accent => switch (widget.special) {
    CardSpecial.blu => CardColors.blueRing,
    CardSpecial.neroOro => CardColors.goldText,
    null => switch (tierOf(widget.member.overall)) {
      CardTier.vuota => MilanacColors.ivory,
      final tier => CardColors.tier(tier),
    },
  };

  /// Fuochi d'artificio per le carte speciali e dall'oro in su.
  bool get _fireworks =>
      widget.special != null ||
      tierOf(widget.member.overall).index >= CardTier.oro.index;

  int? get _up {
    final m = widget.member;
    final before = widget.previousOverall;
    return before != null && m.overall != null ? m.overall! - before : null;
  }

  String get _packName => switch (widget.special) {
    null => (_up ?? 0) > 0 ? 'POTENZIAMENTO' : 'BENVENUTO',
    _ => 'SPECIALE',
  };

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

  /// Punti che l'overall guadagna sulla carta appena ferma: quelli in più rispetto a
  /// prima o il bonus della carta speciale.
  int get _countTo => widget.special != null
      ? max(0, widget.bonus)
      : (widget.member.overall == null ? 0 : max(0, _up ?? 0));

  /// Punti già aggiunti al momento [t].
  int _counting(double t) {
    final n = _countTo;
    if (n == 0 || t < _flipEnd) return 0;
    final q = ((t - _flipEnd) / (_countEnd - _flipEnd)).clamp(0.0, 1.0);
    return (n * Curves.easeOut.transform(q)).round();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MilanacColors.black,
    body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      onVerticalDragUpdate: _opened ? null : _onPull,
      onVerticalDragEnd: _opened ? null : _onPullEnd,
      onVerticalDragCancel: _opened
          ? null
          : () => _pull.animateTo(0, curve: Curves.easeOut),
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: Listenable.merge([_c, _enter, _idle, _pull]),
          builder: (context, _) => _scene(box.biggest),
        ),
      ),
    ),
  );

  Widget _scene(Size size) {
    final m = widget.member;
    final t = _c.value;
    final idle = _idle.value;
    final pulse = (sin(idle * 2 * pi) + 1) / 2;
    // Secondi dallo strappo (negativi prima) e luci dello stadio che si accendono.
    final torn = (t - _tearAt) * _seconds;
    final lights = _opened ? ((t - _tearAt) / .05).clamp(0.0, 1.0) : 0.0;
    final beams = t < _flipAt
        ? lights
        : (1 - (t - _flipAt) / (_flipEnd - _flipAt)).clamp(0.0, 1.0);
    final settle = ((t - _flipEnd) / (1 - _flipEnd)).clamp(0.0, 1.0);
    // La bustina, un po' sopra il centro; lo strappo è dove parte l'esplosione.
    final packW = min(
      250.0,
      min(size.width * .6, size.height * .5 * PackArt.width / PackArt.height),
    );
    final packH = packW * PackArt.height / PackArt.width;
    final packTop = (size.height - packH) / 2 - 24;
    final seam = Offset(
      .5,
      (packTop + packH * PackArt.seam) / max(1, size.height),
    );
    // Il lampo dello strappo: bianco, poi del colore della carta.
    final flash = torn < -.06 || torn > .7
        ? 0.0
        : torn < 0
        ? .9 * (1 + torn / .06)
        : .9 * pow(1 - torn / .7, 2);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: WalkoutBackdropPainter(
            color: Color.lerp(MilanacColors.gold, _accent, lights)!,
            glow: _opened ? .25 + .75 * t : .16 + .1 * pulse,
            beams: beams,
            spin: t * pi * .9,
            twinkle: _opened ? t * 40 : idle * 2 * pi,
            lights: lights,
          ),
        ),
        // I fuochi d'artificio sopra lo stadio, dietro la carta.
        if (_opened && _fireworks)
          IgnorePointer(
            child: CustomPaint(painter: BurstPainter(_fireworksAt(t))),
          ),
        if (!_opened || t < _tearAt + .1)
          Positioned(
            left: (size.width - packW) / 2,
            top: packTop,
            width: packW,
            height: packH,
            child: Semantics(
              button: true,
              label: 'Apri il pacchetto',
              onTap: _open,
              excludeSemantics: true,
              child: OpeningPack(
                name: _packName,
                color: _accent,
                entry: _enter.value,
                float: idle,
                pull: _pull.value,
                shake: _opened ? (t / _tearAt).clamp(0.0, 1.0) : 0,
                burst: _opened ? ((t - _tearAt) / .1).clamp(0.0, 1.0) : 0,
                // Il riflesso passa sulla stagnola all'inizio di ogni giro.
                shine: idle < .45 ? idle / .45 : null,
              ),
            ),
          ),
        if (!_opened)
          Positioned(
            left: 24,
            right: 24,
            top: packTop + packH + 22,
            child: ExcludeSemantics(
              child: Opacity(
                opacity: _enter.value * (.55 + .45 * pulse),
                child: Column(
                  children: [
                    Transform.translate(
                      offset: Offset(0, -5 * pulse),
                      child: const Icon(
                        Icons.keyboard_double_arrow_up_rounded,
                        color: MilanacColors.goldLight,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tocca per aprire',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: sportFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: MilanacColors.ivory,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
          child: Image.asset('assets/images/stemma_256.png', height: 170),
        ),
        // Titolo, carta e frase, come nella tavola del walkout.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 70, 24, 120),
            child: Column(
              children: [
                _heading(t),
                const SizedBox(height: 18),
                Flexible(
                  child: t >= _flipAt ? _card(t) : const SizedBox.shrink(),
                ),
                const SizedBox(height: 18),
                Opacity(
                  opacity: settle,
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
        // L'esplosione dello strappo.
        if (_opened && torn < BurstPainter.life)
          IgnorePointer(
            child: CustomPaint(
              painter: BurstPainter([
                Burst(
                  at: seam,
                  seconds: torn,
                  color: _accent,
                  count: 70,
                  speed: 900,
                  seed: 11,
                  ring: true,
                ),
              ]),
            ),
          ),
        if (flash > 0)
          IgnorePointer(
            child: ColoredBox(
              color: Color.lerp(
                Colors.white,
                _accent,
                (torn / .5).clamp(0.0, 1.0),
              )!.withValues(alpha: flash),
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
                    backgroundColor: MilanacColors.black.withValues(alpha: .5),
                    side: BorderSide(
                      color: MilanacColors.goldLight.withValues(alpha: .6),
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
  }

  /// Tre fuochi che salgono dallo stadio, uno per rivelazione, e due quando la carta
  /// si ferma.
  List<Burst> _fireworksAt(double t) {
    final seconds = _seconds;
    Burst shot(double at, Offset to, int seed, Color color) => Burst(
      at: to,
      seconds: (t - at) * seconds,
      color: color,
      count: 42,
      speed: 380,
      seed: seed,
      launch: Offset(to.dx, .86),
    );
    return [
      shot(_flagAt + .03, const Offset(.2, .2), 21, _accent),
      shot(
        _positionAt + .03,
        const Offset(.8, .16),
        22,
        MilanacColors.goldLight,
      ),
      shot(_crestAt + .03, const Offset(.5, .1), 23, _accent),
      shot(_flipEnd + .02, const Offset(.24, .16), 24, _accent),
      shot(_flipEnd + .05, const Offset(.76, .2), 25, MilanacColors.goldLight),
    ];
  }

  /// In alto: MILANAC PRO CLUB quando si accendono le luci; a carta ferma il titolo,
  /// che entra grande e si assesta.
  Widget _heading(double t) {
    const style = TextStyle(
      fontFamily: sportFont,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: 4,
    );
    if (t < _flipEnd) {
      final on = _opened ? ((t - _tearAt - .03) / .08).clamp(0.0, 1.0) : 0.0;
      return Opacity(
        opacity: t > _flipAt ? .4 * on : on,
        child: Text(
          'MILANAC PRO CLUB',
          textAlign: TextAlign.center,
          style: style.copyWith(color: MilanacColors.ivoryMuted),
        ),
      );
    }
    final p = ((t - _flipEnd) / .05).clamp(0.0, 1.0);
    return Opacity(
      opacity: p,
      child: Transform.scale(
        scale: 1.5 - .5 * Curves.easeOutBack.transform(p),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _title,
            maxLines: 1,
            style: style.copyWith(
              color: _accent,
              shadows: [
                Shadow(color: _accent.withValues(alpha: .7), blurRadius: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// La faccia della carta con i punti già aggiunti: l'overall di prima che sale al
  /// nuovo, o il bonus della carta speciale che si somma.
  Widget _face(int added) {
    final m = widget.member;
    final before = widget.previousOverall;
    return FutCard(
      member: widget.special == null && _countTo > 0 && before != null
          ? m.copyWith(overall: before + added)
          : m,
      special: widget.special,
      bonus: widget.special == null ? 0 : added,
      glow: false,
    );
  }

  /// La carta che gira due volte e si ferma di fronte, con l'esplosione di luce; ferma,
  /// diventa viva (riflesso e inclinazione col dito).
  Widget _card(double t) {
    final p = Curves.easeInOutCubic.transform(
      ((t - _flipAt) / (_flipEnd - _flipAt)).clamp(0, 1),
    );
    // Due giri completi: si ferma di fronte. Tra 90° e 270° si vede il retro.
    final a = (p * 4 * pi) % (2 * pi);
    final front = a < pi / 2 || a > 3 * pi / 2;
    final scale = .55 + .45 * Curves.easeOutBack.transform(p);
    final face = _face(_counting(t));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250),
      child: CustomPaint(
        foregroundPainter: t < _flipEnd
            ? null
            : BurstPainter([
                Burst(
                  at: const Offset(.5, .5),
                  seconds: (t - _flipEnd) * _seconds,
                  color: _accent,
                  count: 44,
                  speed: 620,
                  seed: 5,
                  ring: true,
                ),
              ]),
        child: Transform.scale(
          scale: scale,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0012)
              ..rotateY(front ? a : a - pi),
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
              child: t >= 1
                  ? LiveCard(special: widget.special, child: face)
                  : front
                  ? face
                  : const FutCardBack(),
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
