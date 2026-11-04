import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'board_model.dart';
import 'board_overlays.dart';

// Il campo, i gettoni e il pallone sono oggetti "di gioco": stessi colori nei due temi.

/// Colore del gettone: oro per noi (MILANAC e Futuro), nero per gli avversari.
Color tokenColor(String side) =>
    side == 'avversari' ? MilanacColors.black : MilanacColors.gold;

Color tokenTextColor(String side) =>
    side == 'avversari' ? MilanacColors.ivory : MilanacColors.ink;

/// Il bordo sottile intorno al campo (un velo d'avorio sul verde notte).
final pitchBorderColor = Color.alphaBlend(
  MilanacColors.ivory.withValues(alpha: .12),
  MilanacColors.pitch,
);

/// Il pallone in volo (passaggio o tiro) alla frazione [t] (da 0 a 1) del volo: solo
/// disegno, lo stato della lavagna è già quello d'arrivo.
@immutable
class BallFlight {
  const BallFlight(this.kick, this.t);
  final BallKick kick;
  final double t;

  /// Il pallone parte forte e rallenta arrivando.
  double get eased => Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
}

/// I giocatori che scivolano verso le posizioni della nuova zona, alla frazione [t]
/// (da 0 a 1): solo disegno, lo stato della lavagna è già quello d'arrivo.
@immutable
class ShiftFrame {
  const ShiftFrame(this.shift, this.t);
  final TokenShift shift;
  final double t;

  double get eased => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
}

/// Disegna la lavagna: campo, heatmap, frecce, linee del pallone, gettoni e pallone
/// (coordinate 0..1 sul campo). Per le lavagne ferme (anteprime, immagine dello
/// schema); quella che cambia mentre si disegna o durante il replay è [BoardCanvas].
class BoardPainter extends CustomPainter {
  const BoardPainter(
    this.state, {
    this.pendingArrow,
    this.selectedId,
    this.showNames = true,
  });
  final BoardState state;

  /// Freccia in corso di disegno (dal punto iniziale al dito).
  final BoardArrow? pendingArrow;
  final String? selectedId;
  final bool showNames;

  /// Il rettangolo delle linee del campo, dentro un margine sottile.
  static Rect fieldRect(Size size) =>
      (Offset.zero & size).deflate(size.width * .028);

  /// Da coordinate 0..1 a pixel (e viceversa).
  static Offset toPixel(Size size, double x, double y) {
    final f = fieldRect(size);
    return Offset(f.left + x * f.width, f.top + y * f.height);
  }

  static (double, double) toField(Size size, Offset p) {
    final f = fieldRect(size);
    return (
      ((p.dx - f.left) / f.width).clamp(0.0, 1.0),
      ((p.dy - f.top) / f.height).clamp(0.0, 1.0),
    );
  }

  /// Raggio di un gettone in pixel.
  static double tokenRadius(Size size) => size.width * .042;

  /// Raggio del pallone in pixel (poco più di metà gettone).
  static double ballRadius(Size size) => size.width * .024;

  /// L'area di rigore, larga e profonda; le altre misure del campo si ricavano da
  /// lei con le proporzioni vere (40,32 × 16,5 m).
  static double penaltyBoxWidth(Size size) => size.width * .447;
  static double penaltyBoxDepth(Size size) => fieldRect(size).height * .14;

  /// La porta: 7,32 m sui 40,32 dell'area.
  static double goalWidth(Size size) => penaltyBoxWidth(size) * 7.32 / 40.32;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPitch(canvas, size);
    _paintHeat(canvas, size, state.heat);
    _paintPieces(
      canvas,
      size,
      state,
      pendingArrow: pendingArrow,
      selectedId: selectedId,
      showNames: showNames,
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.state != state ||
      old.pendingArrow != pendingArrow ||
      old.selectedId != selectedId ||
      old.showNames != showNames;
}

/// La cornice del campo: angoli arrotondati e bordo sottile.
class PitchFrame extends StatelessWidget {
  const PitchFrame({super.key, required this.child, this.radius = 16});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: pitchBorderColor),
        ),
        child: child,
      ),
    );
  }
}

/// La lavagna che cambia (mentre si disegna o durante il replay), a livelli: il campo
/// non si ridisegna mai, la heatmap solo quando cambia; frecce, linee, gettoni e
/// pallone si ridisegnano a ogni mossa (e durante il volo del pallone) senza
/// ricostruire la pagina.
class BoardCanvas extends StatefulWidget {
  const BoardCanvas({
    super.key,
    required this.board,
    this.pendingArrow,
    this.flight,
    this.shift,
    this.target,
    this.selectedId,
    this.showNames = true,
  });

  /// La lavagna da seguire (l'editor o il replay).
  final ValueListenable<BoardState> board;

  /// Freccia in corso di disegno (dal punto iniziale al dito).
  final ValueListenable<BoardArrow?>? pendingArrow;

  /// Il pallone in volo (passaggi, tiri e cross).
  final ValueListenable<BallFlight?>? flight;

  /// I giocatori che scivolano verso le posizioni della nuova zona.
  final ValueListenable<ShiftFrame?>? shift;

  /// Il gettone che prenderebbe il pallone lasciato lì (mentre lo si trascina).
  final ValueListenable<String?>? target;
  final String? selectedId;
  final bool showNames;

  @override
  State<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<BoardCanvas> {
  // Avvisano solo quando cambia davvero qualcosa (il replay avvisa a ogni istante,
  // l'editor anche all'inizio di un trascinamento).
  late final _state = ValueNotifier<BoardState>(widget.board.value);
  late final _heat = ValueNotifier<List<HeatPoint>>(widget.board.value.heat);

  @override
  void initState() {
    super.initState();
    widget.board.addListener(_sync);
  }

  @override
  void didUpdateWidget(BoardCanvas old) {
    super.didUpdateWidget(old);
    if (old.board != widget.board) {
      old.board.removeListener(_sync);
      widget.board.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final s = widget.board.value;
    _state.value = s;
    _heat.value = s.heat;
  }

  @override
  void dispose() {
    widget.board.removeListener(_sync);
    _state.dispose();
    _heat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const RepaintBoundary(child: CustomPaint(painter: _PitchLayer())),
      RepaintBoundary(child: CustomPaint(painter: _HeatLayer(_heat))),
      RepaintBoundary(
        child: CustomPaint(
          painter: _PiecesLayer(
            _state,
            pendingArrow: widget.pendingArrow,
            flight: widget.flight,
            shift: widget.shift,
            target: widget.target,
            selectedId: widget.selectedId,
            showNames: widget.showNames,
          ),
        ),
      ),
    ],
  );
}

class _PitchLayer extends CustomPainter {
  const _PitchLayer();

  @override
  void paint(Canvas canvas, Size size) => _paintPitch(canvas, size);

  @override
  bool shouldRepaint(covariant _PitchLayer old) => false;
}

class _HeatLayer extends CustomPainter {
  _HeatLayer(this.heat) : super(repaint: heat);
  final ValueListenable<List<HeatPoint>> heat;

  @override
  void paint(Canvas canvas, Size size) => _paintHeat(canvas, size, heat.value);

  @override
  bool shouldRepaint(covariant _HeatLayer old) => old.heat != heat;
}

class _PiecesLayer extends CustomPainter {
  _PiecesLayer(
    this.board, {
    this.pendingArrow,
    this.flight,
    this.shift,
    this.target,
    this.selectedId,
    required this.showNames,
  }) : super(
         repaint: Listenable.merge([
           board,
           ?pendingArrow,
           ?flight,
           ?shift,
           ?target,
         ]),
       );
  final ValueListenable<BoardState> board;
  final ValueListenable<BoardArrow?>? pendingArrow;
  final ValueListenable<BallFlight?>? flight;
  final ValueListenable<ShiftFrame?>? shift;
  final ValueListenable<String?>? target;
  final String? selectedId;
  final bool showNames;

  @override
  void paint(Canvas canvas, Size size) => _paintPieces(
    canvas,
    size,
    board.value,
    pendingArrow: pendingArrow?.value,
    flight: flight?.value,
    shift: shift?.value,
    targetId: target?.value,
    selectedId: selectedId,
    showNames: showNames,
  );

  @override
  bool shouldRepaint(covariant _PiecesLayer old) =>
      old.board != board ||
      old.pendingArrow != pendingArrow ||
      old.flight != flight ||
      old.shift != shift ||
      old.target != target ||
      old.selectedId != selectedId ||
      old.showNames != showNames;
}

/// Il campo notturno con le linee color oro: bordo, metà campo, cerchio e dischetto
/// di centrocampo, aree di rigore con dischetto e lunetta, aree di porta, porte e
/// bandierine. Le misure vengono dall'area di rigore (come la formazione), con le
/// proporzioni del campo vero.
void _paintPitch(Canvas canvas, Size size) {
  canvas.drawRect(Offset.zero & size, Paint()..color = MilanacColors.pitch);
  final f = BoardPainter.fieldRect(size);
  final w = size.width;
  final line = Paint()
    ..color = MilanacColors.pitchLine
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, w * .0042);
  final dot = Paint()..color = MilanacColors.pitchLine;
  final spot = max(1.5, w * .0075);
  canvas.drawRRect(RRect.fromRectAndRadius(f, Radius.circular(w * .017)), line);
  canvas.drawLine(
    Offset(f.left, f.center.dy),
    Offset(f.right, f.center.dy),
    line,
  );
  canvas.drawCircle(f.center, w * .112, line);
  canvas.drawCircle(f.center, spot, dot);

  final boxW = BoardPainter.penaltyBoxWidth(size);
  final boxH = BoardPainter.penaltyBoxDepth(size);
  final sixW = boxW * 18.32 / 40.32, sixH = boxH * 5.5 / 16.5;
  final goalW = BoardPainter.goalWidth(size), goalD = w * .02;
  final arcR = boxH * 9.15 / 16.5;
  // La lunetta è l'arco del cerchio di 9,15 m dal dischetto che resta fuori
  // dall'area (il dischetto è a 11 m, a due terzi della profondità).
  final arcHalf = acos((boxH / 3) / arcR);
  final goal = Paint()
    ..color = MilanacColors.ivory.withValues(alpha: .7)
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.2, w * .005);
  final net = Paint()..color = MilanacColors.ivory.withValues(alpha: .08);
  final cx = f.center.dx;
  for (final top in [true, false]) {
    // Verso il centro del campo: in giù per la porta in alto, in su per l'altra.
    final s = top ? 1.0 : -1.0;
    final end = top ? f.top : f.bottom;
    Path open(double width, double depth) => Path()
      ..moveTo(cx - width / 2, end)
      ..lineTo(cx - width / 2, end + s * depth)
      ..lineTo(cx + width / 2, end + s * depth)
      ..lineTo(cx + width / 2, end);
    // Area di rigore e area di porta, aperte verso la linea di fondo.
    canvas
      ..drawPath(open(boxW, boxH), line)
      ..drawPath(open(sixW, sixH), line);
    final penalty = Offset(cx, end + s * boxH * 2 / 3);
    canvas
      ..drawCircle(penalty, spot, dot)
      ..drawArc(
        Rect.fromCircle(center: penalty, radius: arcR),
        (top ? pi / 2 : -pi / 2) - arcHalf,
        2 * arcHalf,
        false,
        line,
      );
    // La porta, oltre la linea di fondo (nel margine), con un velo di rete.
    canvas
      ..drawRect(
        Rect.fromLTRB(
          cx - goalW / 2,
          top ? end - goalD : end,
          cx + goalW / 2,
          top ? end : end + goalD,
        ),
        net,
      )
      ..drawPath(open(goalW, -goalD), goal);
  }
  // Bandierine: un quarto di cerchio in ogni angolo.
  final corner = w * .03;
  for (final (c, from) in [
    (f.topLeft, 0.0),
    (f.topRight, pi / 2),
    (f.bottomRight, pi),
    (f.bottomLeft, -pi / 2),
  ]) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: corner),
      from,
      pi / 2,
      false,
      line,
    );
  }
}

/// Heatmap: ogni passaggio del pennello aggiunge un alone d'oro; dove si insiste
/// il colore si fa pieno.
void _paintHeat(Canvas canvas, Size size, List<HeatPoint> heat) {
  if (heat.isEmpty) return;
  canvas.save();
  canvas.clipRect(BoardPainter.fieldRect(size));
  final r = size.width * .075;
  final glow = Paint()
    ..shader = RadialGradient(
      colors: [
        MilanacColors.goldLight.withValues(alpha: .4),
        MilanacColors.gold.withValues(alpha: .22),
        MilanacColors.gold.withValues(alpha: 0),
      ],
      stops: const [0, .55, 1],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
  for (final h in heat) {
    final c = BoardPainter.toPixel(size, h.x, h.y);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.drawCircle(Offset.zero, r, glow);
    canvas.restore();
  }
  canvas.restore();
}

/// Sotto: le zone della palla (posizioni per zona), le zone di battuta, le linee di
/// reparto e del fuorigioco; poi frecce (con quella in corso di disegno, in oro), linee
/// del pallone, gettoni con le bandierine del fuorigioco, i numeri delle zone di
/// battuta e, sopra tutto, il pallone (in volo, se c'è un passaggio in corso). I
/// gettoni che scivolano verso le posizioni della nuova zona ([shift]) si disegnano a
/// metà strada, e le linee li seguono.
void _paintPieces(
  Canvas canvas,
  Size size,
  BoardState state, {
  BoardArrow? pendingArrow,
  BallFlight? flight,
  ShiftFrame? shift,
  String? targetId,
  String? selectedId,
  bool showNames = true,
}) {
  if (shift != null) {
    final e = shift.eased;
    state = state.copyWith(
      tokens: [
        for (final t in state.tokens)
          if (shift.shift.from[t.id] case (final fx, final fy))
            t.moved(fx + (t.x - fx) * e, fy + (t.y - fy) * e)
          else
            t,
      ],
    );
  }
  if (state.shows(BoardOverlay.zonePositions)) {
    _paintBallZones(canvas, size, state);
  }
  final zones = state.shows(BoardOverlay.zones)
      ? deliveryZones(state)
      : const <DeliveryZone>[];
  for (final z in zones) {
    _paintDeliveryZone(canvas, size, z);
  }
  if (state.shows(BoardOverlay.units)) {
    if (readUnits(state) case final units?) _paintUnits(canvas, size, units);
  }
  final offside = state.shows(BoardOverlay.offside) ? readOffside(state) : null;
  if (offside != null) _paintOffsideLines(canvas, size, offside);
  for (final a in state.arrows) {
    _paintArrow(canvas, size, a, MilanacColors.ivory);
  }
  if (state.shows(BoardOverlay.ballLines)) {
    _paintBallLines(canvas, size, state.lines, flight);
  }
  if (pendingArrow != null) {
    _paintArrow(canvas, size, pendingArrow, MilanacColors.goldLight);
  }
  for (final t in state.tokens) {
    _paintToken(
      canvas,
      size,
      t,
      selected: t.id == selectedId,
      target: t.id == targetId,
      showNames: showNames,
    );
  }
  if (offside != null) {
    for (final t in state.tokens) {
      if (offside.flagged.contains(t.id)) _paintOffsideFlag(canvas, size, t);
    }
  }
  for (final z in zones) {
    _paintZoneBadge(canvas, size, z);
  }
  final ball = state.ball;
  if (ball != null) {
    var at = BoardPainter.toPixel(size, ball.x, ball.y);
    if (flight != null) {
      final from = BoardPainter.toPixel(
        size,
        flight.kick.fromX,
        flight.kick.fromY,
      );
      final e = flight.eased;
      final cross = state.lines.any(
        (l) => l.n == flight.kick.line && l.kind == BallLineKind.cross,
      );
      if (cross) {
        // Il cross gira: il pallone segue la curva della sua linea.
        final c = crossControl(size, from, at);
        at = from * ((1 - e) * (1 - e)) + c * (2 * (1 - e) * e) + at * (e * e);
      } else {
        at = Offset.lerp(from, at, e)!;
      }
    }
    paintBall(canvas, at, BoardPainter.ballRadius(size));
  }
}

/// Il punto di controllo della curva di un cross da [p1] a [p2] (in pixel): la palla
/// gira verso il centro del campo, lontano dalla linea di fondo.
Offset crossControl(Size size, Offset p1, Offset p2) {
  final mid = (p1 + p2) / 2;
  final d = p2 - p1;
  final length = d.distance;
  if (length < 1) return mid;
  var n = Offset(-d.dy, d.dx) / length;
  final toCenter = BoardPainter.fieldRect(size).center - mid;
  if (n.dx * toCenter.dx + n.dy * toCenter.dy < 0) n = -n;
  return mid + n * (length * .18);
}

/// Posizioni per zona: le 9 zone della palla a righe sottili, quella del pallone
/// appena accesa e un segno di spunta dove le posizioni sono salvate.
void _paintBallZones(Canvas canvas, Size size, BoardState state) {
  final f = BoardPainter.fieldRect(size);
  final w = size.width;
  final ball = state.ball;
  if (ball != null) {
    final zone = ballZoneAt(ball.x, ball.y);
    canvas.drawRect(
      Rect.fromLTWH(
        f.left + (zone % 3) * f.width / 3,
        f.top + (zone ~/ 3) * f.height / 3,
        f.width / 3,
        f.height / 3,
      ),
      Paint()..color = MilanacColors.ivory.withValues(alpha: .06),
    );
  }
  final grid = Paint()
    ..color = MilanacColors.ivory.withValues(alpha: .22)
    ..strokeWidth = max(1.0, w * .003);
  final dash = w * .02, gap = w * .016;
  for (final i in [1, 2]) {
    final x = f.left + f.width * i / 3, y = f.top + f.height * i / 3;
    for (var d = 0.0; d < f.height; d += dash + gap) {
      canvas.drawLine(
        Offset(x, f.top + d),
        Offset(x, f.top + min(d + dash, f.height)),
        grid,
      );
    }
    for (var d = 0.0; d < f.width; d += dash + gap) {
      canvas.drawLine(
        Offset(f.left + d, y),
        Offset(f.left + min(d + dash, f.width), y),
        grid,
      );
    }
  }
  // La spunta nell'angolo in alto a destra della zona.
  final r = w * .022;
  for (final zone in state.positions.keys) {
    final c = Offset(
      f.left + (zone % 3 + 1) * f.width / 3 - r * 1.5,
      f.top + (zone ~/ 3) * f.height / 3 + r * 1.5,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()..color = MilanacColors.gold.withValues(alpha: .85),
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * .5, c.dy)
        ..lineTo(c.dx - r * .12, c.dy + r * .4)
        ..lineTo(c.dx + r * .5, c.dy - r * .38),
      Paint()
        ..color = MilanacColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * .26)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

/// Una zona di battuta: un rettangolo tenue (il numero lo mette [_paintZoneBadge],
/// sopra i gettoni).
void _paintDeliveryZone(Canvas canvas, Size size, DeliveryZone z) {
  final c = BoardPainter.toPixel(size, z.x, z.y);
  final f = BoardPainter.fieldRect(size);
  final rect = RRect.fromRectAndRadius(
    Rect.fromCenter(center: c, width: z.w * f.width, height: z.h * f.height),
    Radius.circular(size.width * .012),
  );
  canvas
    ..drawRRect(
      rect,
      Paint()..color = MilanacColors.ivory.withValues(alpha: .08),
    )
    ..drawRRect(
      rect,
      Paint()
        ..color = MilanacColors.ivory.withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, size.width * .003),
    );
}

/// Il numero della zona di battuta, nel suo angolo.
void _paintZoneBadge(Canvas canvas, Size size, DeliveryZone z) {
  final w = size.width;
  final r = w * .019;
  final at = BoardPainter.toPixel(size, z.badgeX, z.badgeY);
  canvas
    ..drawCircle(
      at,
      r,
      Paint()..color = MilanacColors.black.withValues(alpha: .72),
    )
    ..drawCircle(
      at,
      r,
      Paint()
        ..color = MilanacColors.ivory.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(.8, w * .0025),
    );
  _text(
    canvas,
    '${z.n}',
    at,
    fontSize: w * .025,
    fontFamily: sportFont,
    weight: FontWeight.w600,
    color: MilanacColors.ivory,
    maxWidth: r * 2.4,
  );
}

/// Le linee di reparto: una linea d'oro per reparto (da sinistra a destra) e, al lato
/// più libero, i metri tra la difesa e il reparto dopo.
void _paintUnits(Canvas canvas, Size size, UnitLines units) {
  final w = size.width;
  final r = BoardPainter.tokenRadius(size);
  final paint = Paint()
    ..color = MilanacColors.goldLight.withValues(alpha: .75)
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, w * .0045)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final group in units.groups) {
    final points = [
      for (final (x, y) in group) BoardPainter.toPixel(size, x, y),
    ];
    if (points.length == 1) {
      // Un reparto di uno: un trattino orizzontale.
      final p = points.single;
      canvas.drawLine(p - Offset(r * 1.8, 0), p + Offset(r * 1.8, 0), paint);
      continue;
    }
    canvas.drawPath(Path()..addPolygon(points, false), paint);
  }
  // I metri: dove c'è più spazio, a sinistra o a destra.
  final y1 = UnitLines.meanY(units.groups[0]);
  final y2 = UnitLines.meanY(units.groups[1]);
  final all = [for (final g in units.groups) ...g];
  double room(double x) => all.fold(
    double.infinity,
    (m, p) => min(m, fieldDistance(p.$1 - x, p.$2 - (y1 + y2) / 2)),
  );
  final x = room(.04) >= room(.96) ? .04 : .96;
  final top = BoardPainter.toPixel(size, x, y2);
  final bottom = BoardPainter.toPixel(size, x, y1);
  final bracket = Paint()
    ..color = MilanacColors.goldLight.withValues(alpha: .85)
    ..strokeWidth = max(1.0, w * .003);
  final tick = w * .012;
  canvas
    ..drawLine(top, bottom, bracket)
    ..drawLine(top - Offset(tick, 0), top + Offset(tick, 0), bracket)
    ..drawLine(bottom - Offset(tick, 0), bottom + Offset(tick, 0), bracket);
  final mid = (top + bottom) / 2;
  final label = '${units.gapMetres} m';
  final fontSize = w * .028;
  final pill = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: mid,
      width: fontSize * (label.length * .62 + 1.2),
      height: fontSize * 1.5,
    ),
    Radius.circular(fontSize),
  );
  canvas.drawRRect(
    pill,
    Paint()..color = MilanacColors.black.withValues(alpha: .8),
  );
  _text(
    canvas,
    label,
    mid,
    fontSize: fontSize,
    fontFamily: sportFont,
    weight: FontWeight.w600,
    color: MilanacColors.goldLight,
    maxWidth: w * .2,
  );
}

/// Il fuorigioco: la linea tratteggiata del penultimo avversario (avorio) e la
/// nostra linea difensiva (oro), da una parte all'altra del campo.
void _paintOffsideLines(Canvas canvas, Size size, OffsideReading o) {
  final w = size.width;
  final f = BoardPainter.fieldRect(size);
  final dash = w * .026, gap = w * .014;
  for (final (y, color) in [
    (o.ourLine, MilanacColors.gold),
    (o.line, MilanacColors.ivory),
  ]) {
    if (y == null) continue;
    final py = BoardPainter.toPixel(size, 0, y).dy;
    final shadow = Paint()
      ..color = MilanacColors.black.withValues(alpha: .4)
      ..strokeWidth = max(2.0, w * .007);
    final line = Paint()
      ..color = color.withValues(alpha: .9)
      ..strokeWidth = max(1.0, w * .0038);
    for (var d = 0.0; d < f.width; d += dash + gap) {
      final a = Offset(f.left + d, py);
      final b = Offset(f.left + min(d + dash, f.width), py);
      canvas
        ..drawLine(a, b, shadow)
        ..drawLine(a, b, line);
    }
  }
}

/// La bandierina del guardalinee sopra il gettone in fuorigioco.
void _paintOffsideFlag(Canvas canvas, Size size, BoardToken t) {
  final c = BoardPainter.toPixel(size, t.x, t.y);
  final r = BoardPainter.tokenRadius(size);
  final foot = c + Offset(r * .75, -r * .45);
  final top = foot - Offset(0, r * 1.3);
  final pole = Paint()
    ..color = MilanacColors.ivory
    ..strokeWidth = max(1.2, r * .14)
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(foot, top, pole);
  final flag = Path()
    ..moveTo(top.dx, top.dy)
    ..lineTo(top.dx + r * .85, top.dy + r * .28)
    ..lineTo(top.dx, top.dy + r * .62)
    ..close();
  canvas
    ..drawPath(
      flag,
      Paint()
        ..color = MilanacColors.black.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * .12),
    )
    ..drawPath(flag, Paint()..color = MilanacColors.kitRed);
}

void _paintArrow(Canvas canvas, Size size, BoardArrow a, Color color) {
  final p1 = BoardPainter.toPixel(size, a.x1, a.y1);
  final p2 = BoardPainter.toPixel(size, a.x2, a.y2);
  if ((p2 - p1).distance < 4) return;
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.5, size.width * .0084)
    ..strokeCap = StrokeCap.round;
  final dir = (p2 - p1) / (p2 - p1).distance;
  final head = size.width * .034;
  final end = p2 - dir * head * .6;
  final line = Path()..moveTo(p1.dx, p1.dy);
  if (a.dashed) {
    final total = (end - p1).distance;
    final dash = size.width * .022, gap = size.width * .0196;
    var d = 0.0;
    while (d < total) {
      final s = p1 + dir * d;
      final e = p1 + dir * min(d + dash, total);
      line
        ..moveTo(s.dx, s.dy)
        ..lineTo(e.dx, e.dy);
      d += dash + gap;
    }
  } else {
    line.lineTo(end.dx, end.dy);
  }
  canvas.drawPath(line, paint);
  canvas.drawPath(_arrowHead(p2, dir, head), Paint()..color = color);
}

/// La punta di una freccia in [tip], lunga [head], nella direzione [dir].
Path _arrowHead(Offset tip, Offset dir, double head) {
  final n = Offset(-dir.dy, dir.dx);
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      tip.dx - dir.dx * head + n.dx * head * .5,
      tip.dy - dir.dy * head + n.dy * head * .5,
    )
    ..lineTo(
      tip.dx - dir.dx * head - n.dx * head * .5,
      tip.dy - dir.dy * head - n.dy * head * .5,
    )
    ..close();
}

/// Le linee del pallone, bianche con il numero dell'azione: le più vecchie un po'
/// più tenui. Quella del passaggio in volo cresce con il pallone.
void _paintBallLines(
  Canvas canvas,
  Size size,
  List<BallLine> lines,
  BallFlight? flight,
) {
  for (final (i, l) in lines.indexed) {
    final age = lines.length - 1 - i;
    _paintBallLine(
      canvas,
      size,
      l,
      opacity: max(.4, 1 - age * .05),
      progress: flight != null && flight.kick.line == l.n ? flight.eased : 1,
    );
  }
}

/// Passaggio: linea continua con la punta; conduzione: linea ondulata; tiro: linea
/// spessa fino alla porta. Si accorciano dove toccano un gettone, così punta e numero
/// restano fuori; un filo scuro sotto le stacca dalla heatmap.
void _paintBallLine(
  Canvas canvas,
  Size size,
  BallLine l, {
  required double opacity,
  required double progress,
}) {
  final w = size.width;
  final r = BoardPainter.tokenRadius(size);
  final br = BoardPainter.ballRadius(size);
  final p1 = BoardPainter.toPixel(size, l.x1, l.y1);
  final p2 = BoardPainter.toPixel(size, l.x2, l.y2);
  final trimStart = l.fromPlayer ? r * 1.05 : br * 1.1;
  final trimEnd = l.toPlayer ? r * 1.15 : br * 1.15;
  if (l.kind == BallLineKind.cross) {
    _paintCross(
      canvas,
      size,
      l,
      p1,
      p2,
      trimStart: trimStart,
      trimEnd: trimEnd,
      opacity: opacity,
      progress: progress,
    );
    return;
  }
  final full = (p2 - p1).distance;
  final length = full - trimStart - trimEnd;
  if (!length.isFinite || length < br) return;
  final dir = (p2 - p1) / full;
  final start = p1 + dir * trimStart;
  final tip = start + dir * (length * progress);
  final (width, head) = switch (l.kind) {
    BallLineKind.shot => (max(2.5, w * .011), w * .036),
    BallLineKind.pass || BallLineKind.cross => (max(1.2, w * .0055), w * .028),
    BallLineKind.carry => (max(1.2, w * .0055), w * .024),
  };
  final stem = max(0.0, (tip - start).distance - head * .6);
  final path = Path()..moveTo(start.dx, start.dy);
  if (l.kind == BallLineKind.carry) {
    // L'onda si spegne alle due estremità: parte dal giocatore e finisce nella punta.
    final n = Offset(-dir.dy, dir.dx);
    final amp = w * .008, wave = w * .034;
    for (var d = 0.0; d <= stem; d += max(1.0, w * .004)) {
      final fade = min(1.0, min(d, stem - d) / (wave / 2));
      final p = start + dir * d + n * (amp * fade * sin(2 * pi * d / wave));
      path.lineTo(p.dx, p.dy);
    }
  } else {
    final e = start + dir * stem;
    path.lineTo(e.dx, e.dy);
  }
  final outline = max(1.0, w * .0025);
  final shadow = MilanacColors.black.withValues(alpha: .35 * opacity);
  final color = Colors.white.withValues(alpha: opacity);
  final arrowHead = _arrowHead(tip, dir, head);
  canvas
    ..drawPath(
      path,
      Paint()
        ..color = shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + outline * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(
      arrowHead,
      Paint()
        ..color = shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline * 2
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(arrowHead, Paint()..color = color);
  // Il numero, piccolo, all'inizio della linea.
  _lineNumber(
    canvas,
    size,
    start + dir * min(length / 2, w * .02 * 1.4),
    l.n,
    opacity,
  );
}

/// Il numero dell'azione del pallone, in un cerchietto scuro.
void _lineNumber(Canvas canvas, Size size, Offset at, int n, double opacity) {
  final w = size.width;
  final badge = w * .02;
  canvas
    ..drawCircle(
      at,
      badge,
      Paint()..color = MilanacColors.black.withValues(alpha: .82 * opacity),
    )
    ..drawCircle(
      at,
      badge,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(.8, w * .0028),
    );
  _text(
    canvas,
    '$n',
    at,
    fontSize: w * .025,
    fontFamily: sportFont,
    weight: FontWeight.w600,
    color: MilanacColors.ivory.withValues(alpha: opacity),
    maxWidth: badge * 2.4,
  );
}

/// Il cross: una linea a puntini che gira verso il centro del campo, con la punta
/// nella zona di battuta.
void _paintCross(
  Canvas canvas,
  Size size,
  BallLine l,
  Offset p1,
  Offset p2, {
  required double trimStart,
  required double trimEnd,
  required double opacity,
  required double progress,
}) {
  final w = size.width;
  final br = BoardPainter.ballRadius(size);
  final c = crossControl(size, p1, p2);
  // Le misure del percorso si leggono una volta sola (l'iteratore non riparte).
  final metrics =
      (Path()
            ..moveTo(p1.dx, p1.dy)
            ..quadraticBezierTo(c.dx, c.dy, p2.dx, p2.dy))
          .computeMetrics()
          .iterator;
  if (!metrics.moveNext()) return;
  final curve = metrics.current;
  final length = curve.length - trimStart - trimEnd;
  if (!length.isFinite || length < br) return;
  final end = trimStart + length * progress;
  final head = w * .028;
  final dot = max(1.1, w * .0048), step = max(4.0, w * .017);
  final shadow = MilanacColors.black.withValues(alpha: .35 * opacity);
  final color = Colors.white.withValues(alpha: opacity);
  for (var d = trimStart; d <= end - head * .7; d += step) {
    final p = curve.getTangentForOffset(d)!.position;
    canvas
      ..drawCircle(p, dot + max(.8, w * .0022), Paint()..color = shadow)
      ..drawCircle(p, dot, Paint()..color = color);
  }
  final tip = curve.getTangentForOffset(end)!;
  final dir = tip.vector / max(1e-6, tip.vector.distance);
  final arrowHead = _arrowHead(tip.position, dir, head);
  canvas
    ..drawPath(
      arrowHead,
      Paint()
        ..color = shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(2.0, w * .005)
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(arrowHead, Paint()..color = color);
  _lineNumber(
    canvas,
    size,
    curve
        .getTangentForOffset(trimStart + min(length / 2, w * .02 * 1.4))!
        .position,
    l.n,
    opacity,
  );
}

/// Il pallone: bianco con le macchie nere e un'ombra morbida.
void paintBall(Canvas canvas, Offset c, double r) {
  canvas.drawCircle(
    c + Offset(r * .12, r * .38),
    r,
    Paint()
      ..color = MilanacColors.black.withValues(alpha: .5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(.5, r * .35)),
  );
  canvas.drawCircle(c, r, Paint()..color = Colors.white);
  // Un pentagono al centro e cinque sul bordo, in direzione dei suoi vertici.
  final patch = Paint()..color = MilanacColors.ink;
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  canvas.drawPath(_pentagon(c, r * .36, -pi / 2), patch);
  for (var i = 0; i < 5; i++) {
    final a = -pi / 2 + i * 2 * pi / 5;
    canvas.drawPath(
      _pentagon(c + Offset(cos(a), sin(a)) * r * 1.02, r * .36, a + pi),
      patch,
    );
  }
  canvas.restore();
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..color = MilanacColors.ink.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(.6, r * .08),
  );
}

Path _pentagon(Offset c, double r, double rotation) {
  final p = Path();
  for (var i = 0; i < 5; i++) {
    final a = rotation + i * 2 * pi / 5;
    final v = c + Offset(cos(a), sin(a)) * r;
    i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
  }
  return p..close();
}

/// Gettone: cerchio oro (noi) o nero (avversari) con il bordo avorio, il numero e
/// sotto il cognome; quello selezionato ha un anello d'oro, quello che sta per
/// ricevere il pallone trascinato un anello bianco.
void _paintToken(
  Canvas canvas,
  Size size,
  BoardToken t, {
  bool selected = false,
  bool target = false,
  bool showNames = true,
}) {
  final c = BoardPainter.toPixel(size, t.x, t.y);
  final r = BoardPainter.tokenRadius(size);
  final stroke = max(1.5, size.width * .0056);
  if (selected || target) {
    canvas.drawCircle(
      c,
      r + stroke * 2.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = target ? stroke * 1.4 : stroke
        ..color = target ? Colors.white : MilanacColors.goldLight,
    );
  }
  canvas.drawCircle(c, r, Paint()..color = tokenColor(t.side));
  canvas.drawCircle(
    c,
    r - stroke / 2,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = MilanacColors.ivory,
  );
  _text(
    canvas,
    t.label,
    c,
    fontSize: size.width * .037,
    fontFamily: sportFont,
    weight: FontWeight.w600,
    color: tokenTextColor(t.side),
    maxWidth: r * 1.9,
  );
  final surname = _surname(t.name);
  if (showNames && surname.isNotEmpty) {
    final fontSize = size.width * .034;
    _text(
      canvas,
      surname,
      c + Offset(0, r + fontSize * .8),
      fontSize: fontSize,
      fontFamily: bodyFont,
      weight: FontWeight.w700,
      color: MilanacColors.ivory,
      maxWidth: r * 5,
      shadow: true,
    );
  }
}

/// Sotto il gettone va il cognome (l'ultima parola del nome).
String _surname(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.last;
}

/// Testi dei gettoni già impaginati: durante un trascinamento la lavagna si ridisegna
/// a ogni movimento con gli stessi testi. Si tengono gli ultimi usati; quelli che
/// escono si rilasciano.
final _texts =
    <(String, double, String, FontWeight, Color, double, bool), TextPainter>{};
const _maxTexts = 128;

void _text(
  Canvas canvas,
  String s,
  Offset center, {
  required double fontSize,
  required String fontFamily,
  required FontWeight weight,
  required Color color,
  double maxWidth = 200,
  bool shadow = false,
}) {
  final key = (s, fontSize, fontFamily, weight, color, maxWidth, shadow);
  var tp = _texts.remove(key);
  tp ??= TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: .2,
        shadows: shadow
            ? [
                Shadow(
                  color: MilanacColors.black.withValues(alpha: .8),
                  blurRadius: 3,
                ),
              ]
            : null,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  _texts[key] = tp; // in fondo: il più recente
  while (_texts.length > _maxTexts) {
    _texts.remove(_texts.keys.first)!.dispose();
  }
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Il campo è alto 1 / 0.68 volte la larghezza (come la formazione).
const boardAspect = 0.68;

/// La lavagna come immagine PNG (per gli schemi salvati e la condivisione).
Future<Uint8List> renderBoardImage(
  BoardState state, {
  double width = 1080,
}) async {
  final size = Size(width, width / boardAspect);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  BoardPainter(state).paint(canvas, size);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Anteprima ferma della lavagna (nelle card e nel messaggio del replay).
class BoardPreview extends StatelessWidget {
  const BoardPreview({
    super.key,
    required this.state,
    this.showNames = false,
    this.radius = 12,
  });
  final BoardState state;
  final bool showNames;
  final double radius;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: boardAspect,
    child: PitchFrame(
      radius: radius,
      child: CustomPaint(painter: BoardPainter(state, showNames: showNames)),
    ),
  );
}

/// Il pallone da solo, grande [size] (nei fogli della lavagna).
class BallGlyph extends StatelessWidget {
  const BallGlyph({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _BallGlyphPainter()),
  );
}

class _BallGlyphPainter extends CustomPainter {
  const _BallGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      paintBall(canvas, size.center(Offset.zero), size.shortestSide * .42);

  @override
  bool shouldRepaint(covariant _BallGlyphPainter old) => false;
}
