import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'board_model.dart';

// Il campo, i gettoni e il pallone sono oggetti "di gioco": stessi colori nei due temi.

/// Colore del gettone: oro per noi (Milan AC e Futuro), nero per gli avversari.
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
    this.target,
    this.selectedId,
    this.showNames = true,
  });

  /// La lavagna da seguire (l'editor o il replay).
  final ValueListenable<BoardState> board;

  /// Freccia in corso di disegno (dal punto iniziale al dito).
  final ValueListenable<BoardArrow?>? pendingArrow;

  /// Il pallone in volo (passaggi e tiri).
  final ValueListenable<BallFlight?>? flight;

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
    this.target,
    this.selectedId,
    required this.showNames,
  }) : super(
         repaint: Listenable.merge([board, ?pendingArrow, ?flight, ?target]),
       );
  final ValueListenable<BoardState> board;
  final ValueListenable<BoardArrow?>? pendingArrow;
  final ValueListenable<BallFlight?>? flight;
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
    targetId: target?.value,
    selectedId: selectedId,
    showNames: showNames,
  );

  @override
  bool shouldRepaint(covariant _PiecesLayer old) =>
      old.board != board ||
      old.pendingArrow != pendingArrow ||
      old.flight != flight ||
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

/// Frecce (con quella in corso di disegno, in oro), linee del pallone, gettoni e, sopra
/// tutto, il pallone (in volo, se c'è un passaggio in corso).
void _paintPieces(
  Canvas canvas,
  Size size,
  BoardState state, {
  BoardArrow? pendingArrow,
  BallFlight? flight,
  String? targetId,
  String? selectedId,
  bool showNames = true,
}) {
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
  final ball = state.ball;
  if (ball != null) {
    var (x, y) = (ball.x, ball.y);
    if (flight != null) {
      final e = flight.eased;
      x = flight.kick.fromX + (x - flight.kick.fromX) * e;
      y = flight.kick.fromY + (y - flight.kick.fromY) * e;
    }
    paintBall(
      canvas,
      BoardPainter.toPixel(size, x, y),
      BoardPainter.ballRadius(size),
    );
  }
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
  final full = (p2 - p1).distance;
  final trimStart = l.fromPlayer ? r * 1.05 : br * 1.1;
  final trimEnd = l.toPlayer ? r * 1.15 : br * 1.15;
  final length = full - trimStart - trimEnd;
  if (!length.isFinite || length < br) return;
  final dir = (p2 - p1) / full;
  final start = p1 + dir * trimStart;
  final tip = start + dir * (length * progress);
  final (width, head) = switch (l.kind) {
    BallLineKind.shot => (max(2.5, w * .011), w * .036),
    BallLineKind.pass => (max(1.2, w * .0055), w * .028),
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
  final badge = w * .02;
  final at = start + dir * min(length / 2, badge * 1.4);
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
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(.8, w * .0028),
    );
  _text(
    canvas,
    '${l.n}',
    at,
    fontSize: w * .025,
    fontFamily: sportFont,
    weight: FontWeight.w600,
    color: MilanacColors.ivory.withValues(alpha: opacity),
    maxWidth: badge * 2.4,
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
