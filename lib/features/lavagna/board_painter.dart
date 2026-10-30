import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'board_model.dart';

// Il campo e i gettoni sono oggetti "di gioco": stessi colori nei due temi.

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

/// Disegna la lavagna: campo, heatmap, frecce e gettoni (coordinate 0..1 sul campo).
/// Per le lavagne ferme (anteprime, immagine dello schema); quella che cambia mentre
/// si disegna o durante il replay è [BoardCanvas].
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
/// non si ridisegna mai, la heatmap solo quando cambia; frecce e gettoni si
/// ridisegnano a ogni mossa senza ricostruire la pagina.
class BoardCanvas extends StatefulWidget {
  const BoardCanvas({
    super.key,
    required this.board,
    this.pendingArrow,
    this.selectedId,
    this.showNames = true,
  });

  /// La lavagna da seguire (l'editor o il replay).
  final ValueListenable<BoardState> board;

  /// Freccia in corso di disegno (dal punto iniziale al dito).
  final ValueListenable<BoardArrow?>? pendingArrow;
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
    this.selectedId,
    required this.showNames,
  }) : super(
         repaint: pendingArrow == null
             ? board
             : Listenable.merge([board, pendingArrow]),
       );
  final ValueListenable<BoardState> board;
  final ValueListenable<BoardArrow?>? pendingArrow;
  final String? selectedId;
  final bool showNames;

  @override
  void paint(Canvas canvas, Size size) => _paintPieces(
    canvas,
    size,
    board.value,
    pendingArrow: pendingArrow?.value,
    selectedId: selectedId,
    showNames: showNames,
  );

  @override
  bool shouldRepaint(covariant _PiecesLayer old) =>
      old.board != board ||
      old.pendingArrow != pendingArrow ||
      old.selectedId != selectedId ||
      old.showNames != showNames;
}

/// Il campo notturno con le linee color oro: bordo, metà campo, cerchio di
/// centrocampo e aree di rigore (come la formazione).
void _paintPitch(Canvas canvas, Size size) {
  canvas.drawRect(Offset.zero & size, Paint()..color = MilanacColors.pitch);
  final f = BoardPainter.fieldRect(size);
  final line = Paint()
    ..color = MilanacColors.pitchLine
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, size.width * .0042);
  canvas.drawRRect(
    RRect.fromRectAndRadius(f, Radius.circular(size.width * .017)),
    line,
  );
  canvas.drawLine(
    Offset(f.left, f.center.dy),
    Offset(f.right, f.center.dy),
    line,
  );
  canvas.drawCircle(f.center, size.width * .112, line);
  // Aree di rigore, aperte verso la linea di fondo.
  final boxW = size.width * .447, boxH = f.height * .14;
  final left = f.center.dx - boxW / 2, right = left + boxW;
  canvas
    ..drawPath(
      Path()
        ..moveTo(left, f.top)
        ..lineTo(left, f.top + boxH)
        ..lineTo(right, f.top + boxH)
        ..lineTo(right, f.top),
      line,
    )
    ..drawPath(
      Path()
        ..moveTo(left, f.bottom)
        ..lineTo(left, f.bottom - boxH)
        ..lineTo(right, f.bottom - boxH)
        ..lineTo(right, f.bottom),
      line,
    );
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

/// Frecce (con quella in corso di disegno, in oro) e gettoni.
void _paintPieces(
  Canvas canvas,
  Size size,
  BoardState state, {
  BoardArrow? pendingArrow,
  String? selectedId,
  bool showNames = true,
}) {
  for (final a in state.arrows) {
    _paintArrow(canvas, size, a, MilanacColors.ivory);
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
      showNames: showNames,
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
  // Punta.
  final n = Offset(-dir.dy, dir.dx);
  final tip = Path()
    ..moveTo(p2.dx, p2.dy)
    ..lineTo(
      p2.dx - dir.dx * head + n.dx * head * .5,
      p2.dy - dir.dy * head + n.dy * head * .5,
    )
    ..lineTo(
      p2.dx - dir.dx * head - n.dx * head * .5,
      p2.dy - dir.dy * head - n.dy * head * .5,
    )
    ..close();
  canvas.drawPath(tip, Paint()..color = color);
}

/// Gettone: cerchio oro (noi) o nero (avversari) con il bordo avorio, il numero e
/// sotto il cognome; quello selezionato ha un anello d'oro.
void _paintToken(
  Canvas canvas,
  Size size,
  BoardToken t, {
  bool selected = false,
  bool showNames = true,
}) {
  final c = BoardPainter.toPixel(size, t.x, t.y);
  final r = BoardPainter.tokenRadius(size);
  final stroke = max(1.5, size.width * .0056);
  if (selected) {
    canvas.drawCircle(
      c,
      r + stroke * 2.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = MilanacColors.goldLight,
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
