import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../formazione/pitch_painter.dart';
import 'board_model.dart';

/// Colore del gettone secondo la squadra.
Color tokenColor(String side) => switch (side) {
  'futuro' => const Color(0xFF546E7A),
  'avversari' => const Color(0xFFF5F5F5),
  _ => MilanacColors.red,
};

Color tokenTextColor(String side) =>
    side == 'avversari' ? Colors.black87 : Colors.white;

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

  static const inset = PitchPainter.inset;

  /// Da coordinate 0..1 a pixel (e viceversa).
  static Offset toPixel(Size size, double x, double y) => Offset(
    inset + x * (size.width - inset * 2),
    inset + y * (size.height - inset * 2),
  );

  static (double, double) toField(Size size, Offset p) => (
    ((p.dx - inset) / (size.width - inset * 2)).clamp(0.0, 1.0),
    ((p.dy - inset) / (size.height - inset * 2)).clamp(0.0, 1.0),
  );

  /// Raggio di un gettone in pixel.
  static double tokenRadius(Size size) => size.width * .052;

  @override
  void paint(Canvas canvas, Size size) {
    const PitchPainter().paint(canvas, size);
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
      const RepaintBoundary(child: CustomPaint(painter: PitchPainter())),
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

/// Heatmap: ogni passaggio del pennello aggiunge un alone giallo; dove si insiste
/// il centro diventa rosso.
void _paintHeat(Canvas canvas, Size size, List<HeatPoint> heat) {
  if (heat.isEmpty) return;
  canvas.save();
  canvas.clipRect((Offset.zero & size).deflate(BoardPainter.inset));
  final r = size.width * .075;
  final yellow = Paint()
    ..shader = RadialGradient(
      colors: [
        const Color(0xFFFFD600).withValues(alpha: .28),
        Colors.transparent,
      ],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
  final red = Paint()
    ..shader = RadialGradient(
      colors: [
        const Color(0xFFFF1744).withValues(alpha: .16),
        Colors.transparent,
      ],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * .6));
  for (final h in heat) {
    final c = BoardPainter.toPixel(size, h.x, h.y);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.drawCircle(Offset.zero, r, yellow);
    canvas.drawCircle(Offset.zero, r * .6, red);
    canvas.restore();
  }
  canvas.restore();
}

/// Frecce (con quella in corso di disegno) e gettoni.
void _paintPieces(
  Canvas canvas,
  Size size,
  BoardState state, {
  BoardArrow? pendingArrow,
  String? selectedId,
  bool showNames = true,
}) {
  for (final a in state.arrows) {
    _paintArrow(canvas, size, a, Colors.white);
  }
  if (pendingArrow != null) {
    _paintArrow(canvas, size, pendingArrow, MilanacColors.gold);
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
  final stroke = size.width * .009;
  final shadow = Paint()
    ..color = Colors.black.withValues(alpha: .35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke + 2
    ..strokeCap = StrokeCap.round;
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round;
  final dir = (p2 - p1) / (p2 - p1).distance;
  final head = size.width * .035;
  final end = p2 - dir * head * .6;
  final line = Path()..moveTo(p1.dx, p1.dy);
  if (a.dashed) {
    final total = (end - p1).distance;
    final dash = size.width * .03, gap = size.width * .018;
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
  canvas.drawPath(line, shadow);
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
  canvas.drawPath(tip, Paint()..color = Colors.black.withValues(alpha: .35));
  canvas.drawPath(tip, Paint()..color = color);
}

void _paintToken(
  Canvas canvas,
  Size size,
  BoardToken t, {
  bool selected = false,
  bool showNames = true,
}) {
  final c = BoardPainter.toPixel(size, t.x, t.y);
  final r = BoardPainter.tokenRadius(size);
  canvas.drawCircle(
    c + Offset(0, r * .15),
    r,
    Paint()..color = Colors.black.withValues(alpha: .4),
  );
  canvas.drawCircle(c, r, Paint()..color = tokenColor(t.side));
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 2
      ..color = selected ? MilanacColors.gold : Colors.white,
  );
  _text(canvas, t.label, c, r * .95, FontWeight.w700, tokenTextColor(t.side));
  if (showNames && t.name.isNotEmpty) {
    _text(
      canvas,
      t.name.toUpperCase(),
      c + Offset(0, r * 1.75),
      r * .62,
      FontWeight.w600,
      Colors.white,
      maxWidth: r * 5,
      shadow: true,
    );
  }
}

/// Testi dei gettoni già impaginati: durante un trascinamento la lavagna si ridisegna
/// a ogni movimento con gli stessi testi. Si tengono gli ultimi usati; quelli che
/// escono si rilasciano.
final _texts =
    <(String, double, FontWeight, Color, double, bool), TextPainter>{};
const _maxTexts = 128;

void _text(
  Canvas canvas,
  String s,
  Offset center,
  double fontSize,
  FontWeight weight,
  Color color, {
  double maxWidth = 200,
  bool shadow = false,
}) {
  final key = (s, fontSize, weight, color, maxWidth, shadow);
  var tp = _texts.remove(key);
  tp ??= TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: sportFont,
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: .3,
        shadows: shadow
            ? const [Shadow(color: Colors.black, blurRadius: 4)]
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

/// Anteprima statica della lavagna (nelle card e nel messaggio del replay).
class BoardPreview extends StatelessWidget {
  const BoardPreview({super.key, required this.state, this.showNames = false});
  final BoardState state;
  final bool showNames;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: boardAspect,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(painter: BoardPainter(state, showNames: showNames)),
    ),
  );
}
