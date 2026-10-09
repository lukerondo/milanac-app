import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../rosa/member.dart';
import '../volto/face_view.dart';
import 'modules.dart';
import 'pitch_painter.dart';

/// Colori della mini carta secondo l'overall (come i livelli della carta grande).
(Color, Color, Color) _cardColors(int? overall) => switch (overall) {
  null => (const Color(0xFF34343C), const Color(0xFF17171B), Colors.white),
  < 65 => (
    const Color(0xFFD9A273),
    const Color(0xFF8A5530),
    const Color(0xFF3B2414),
  ),
  < 75 => (
    const Color(0xFFF1F3F6),
    const Color(0xFF9AA1AB),
    const Color(0xFF23272E),
  ),
  < 85 => (
    const Color(0xFFFBE3A0),
    const Color(0xFFC99A2E),
    const Color(0xFF3A2A08),
  ),
  _ => (const Color(0xFFC8102E), const Color(0xFF0B0B0D), const Color(0xFFF6D77F)),
};

/// Larghezza "logica" del disegno (il campo come appare nell'app); il PNG è più grande.
const _logicalWidth = 360.0;
const _pitchAspect = 0.68;

/// Immagine della formazione: il campo con una mini carta per ogni titolare
/// (volto, nome sulla carta, ruolo e overall). Disegnata fuori schermo.
Future<Uint8List> renderFormationImage(
  Formation formation,
  Map<String, Member> members, {
  double width = 1080,
}) async {
  final scale = width / _logicalWidth;
  final logical = Size(_logicalWidth, _logicalWidth / _pitchAspect);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  const PitchPainter().paint(canvas, logical);

  const inset = PitchPainter.inset;
  final fieldW = logical.width - inset * 2;
  final fieldH = logical.height - inset * 2;
  for (final (i, slot) in formation.slots.indexed) {
    final center = Offset(inset + slot.x * fieldW, inset + slot.y * fieldH);
    final member = members[formation.players[i]];
    if (member == null) {
      _paintEmptySlot(canvas, center, slot.label);
    } else {
      _paintMiniCard(canvas, center, member, slot.label);
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (logical.width * scale).round(),
    (logical.height * scale).round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

const _cardW = 60.0, _cardH = 78.0;

void _paintEmptySlot(Canvas canvas, Offset center, String label) {
  canvas.drawCircle(
    center,
    16,
    Paint()
      ..color = Colors.black.withValues(alpha: .35)
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    16,
    Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  _text(canvas, label, center, 10, FontWeight.w800, Colors.white);
}

void _paintMiniCard(Canvas canvas, Offset center, Member m, String label) {
  final rect = Rect.fromCenter(center: center, width: _cardW, height: _cardH);
  final (top, bottom, text) = _cardColors(m.overall);
  final rr = RRect.fromRectAndRadius(rect, const Radius.circular(9));
  canvas.drawRRect(
    rr.shift(const Offset(0, 2)),
    Paint()..color = Colors.black.withValues(alpha: .35),
  );
  canvas.drawRRect(
    rr,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(rect),
  );
  canvas.drawRRect(
    rr.deflate(1.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = text.withValues(alpha: .55),
  );

  // Volto (testa) in un cerchio.
  final faceCenter = Offset(center.dx, rect.top + 22);
  const faceR = 16.0;
  final face = m.face;
  canvas.save();
  canvas.clipPath(
    Path()..addOval(Rect.fromCircle(center: faceCenter, radius: faceR)),
  );
  if (face != null) {
    canvas.save();
    canvas.translate(faceCenter.dx - faceR, faceCenter.dy - faceR);
    FacePainter(
      face,
      crop: FaceCrop.head,
      background: Colors.white.withValues(alpha: .18),
    ).paint(canvas, const Size(faceR * 2, faceR * 2));
    canvas.restore();
  } else {
    canvas.drawCircle(
      faceCenter,
      faceR,
      Paint()..color = Colors.white.withValues(alpha: .18),
    );
    _text(
      canvas,
      m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase(),
      faceCenter,
      14,
      FontWeight.w800,
      text,
    );
  }
  canvas.restore();
  canvas.drawCircle(
    faceCenter,
    faceR,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = text.withValues(alpha: .7),
  );

  // Overall e ruolo, poi il nome sulla carta.
  _text(
    canvas,
    '${m.overall?.toString() ?? '–'} $label',
    Offset(center.dx, rect.top + 47),
    11,
    FontWeight.w800,
    text,
  );
  _text(
    canvas,
    m.displayName.toUpperCase(),
    Offset(center.dx, rect.top + 63),
    9,
    FontWeight.w600,
    text,
    maxWidth: _cardW - 8,
  );
}

void _text(
  Canvas canvas,
  String s,
  Offset center,
  double size,
  FontWeight weight,
  Color color, {
  double maxWidth = 120,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: sportFont,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: .3,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Il PDF: titolo, data, modulo, l'immagine del campo e la panchina.
Future<Uint8List> buildFormationPdf({
  required Formation formation,
  required Map<String, Member> members,
  required List<Member> bench,
  required Uint8List image,
  DateTime? date,
}) async {
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Oswald-500.ttf'));
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Oswald-400.ttf'),
  );
  final crest = pw.MemoryImage(
    (await rootBundle.load('assets/images/stemma_256.png')).buffer.asUint8List(),
  );
  final when = DateFormat("EEEE d MMMM yyyy", 'it').format(date ?? DateTime.now());
  final starters = [
    for (final (i, slot) in formation.slots.indexed)
      if (members[formation.players[i]] case final m?)
        '${slot.label} ${m.displayName}',
  ];
  const red = PdfColor.fromInt(0xFFC61C23);
  const gold = PdfColor.fromInt(0xFFD4AF37);

  final doc = pw.Document(
    title: 'Formazione ${formation.team.label}',
    author: 'MILANAC Pro Club',
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            children: [
              pw.Image(crest, width: 46, height: 46),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FORMAZIONE ${formation.team.label.toUpperCase()}',
                    style: pw.TextStyle(font: bold, fontSize: 22, color: red),
                  ),
                  pw.Text(
                    '${when[0].toUpperCase()}${when.substring(1)} · modulo ${formation.module}',
                    style: pw.TextStyle(font: regular, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(height: 2, color: gold),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Image(pw.MemoryImage(image), height: 560),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'TITOLARI',
            style: pw.TextStyle(font: bold, fontSize: 12, color: red),
          ),
          pw.Text(
            starters.isEmpty ? 'Da definire' : starters.join(' · '),
            style: pw.TextStyle(font: regular, fontSize: 10),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'PANCHINA',
            style: pw.TextStyle(font: bold, fontSize: 12, color: red),
          ),
          pw.Text(
            bench.isEmpty
                ? 'Tutti in campo'
                : bench.map((m) => m.displayName).join(' · '),
            style: pw.TextStyle(font: regular, fontSize: 10),
          ),
          pw.Spacer(),
          pw.Text(
            'MILANAC Pro Club · generato dall\'app',
            style: pw.TextStyle(
              font: regular,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Disegna, impagina e condivide il PDF della formazione.
Future<void> shareFormationPdf(
  BuildContext context, {
  required Formation formation,
  required Map<String, Member> members,
  required List<Member> bench,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final image = await renderFormationImage(formation, members);
    final bytes = await buildFormationPdf(
      formation: formation,
      members: members,
      bench: bench,
      image: image,
      date: formation.publishedAt?.toLocal(),
    );
    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'formazione_${formation.team.name}_$day.pdf',
          ),
        ],
        subject: 'Formazione ${formation.team.label}',
        text: 'Formazione ${formation.team.label} (${formation.module})',
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('PDF non creato: $e')));
  }
}
