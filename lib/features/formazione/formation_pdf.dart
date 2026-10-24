import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/italian_time.dart';
import '../../core/theme.dart';
import '../carta/card_design.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../volto/face_view.dart';
import 'modules.dart';
import 'pitch_painter.dart';

/// Larghezza "logica" del disegno (il campo come appare nell'app); il PNG è più grande.
const _logicalWidth = 360.0;
const _pitchAspect = 0.68;

/// Immagine della formazione: il campo con una mini carta per ogni titolare, come
/// quelle dell'app (sagoma e colori della carta, foto o volto, overall, ruolo e nome
/// sulla carta). Disegnata fuori schermo; [photos] sono le foto delle carte (id del
/// membro → immagine) già caricate.
Future<Uint8List> renderFormationImage(
  Formation formation,
  Map<String, Member> members, {
  double width = 1080,
  Map<String, SpecialCard> specials = const {},
  Map<String, ui.Image> photos = const {},
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
      _paintMiniCard(
        canvas,
        center,
        member,
        slot.label,
        specials[member.id],
        photos[member.id],
      );
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

const _cardW = 60.0, _cardH = 84.0;

void _paintEmptySlot(Canvas canvas, Offset center, String label) {
  canvas.drawCircle(
    center,
    16,
    Paint()
      ..color = MilanacColors.ink.withValues(alpha: .4)
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    16,
    Paint()
      ..color = MilanacColors.ivory.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  _text(canvas, label, center, 10, FontWeight.w800, MilanacColors.ivory);
}

void _paintMiniCard(
  Canvas canvas,
  Offset center,
  Member m,
  String label,
  SpecialCard? special,
  ui.Image? photo,
) {
  final rect = Rect.fromCenter(center: center, width: _cardW, height: _cardH);
  const size = Size(_cardW, _cardH);
  final design = CardDesign.of(special?.kind, m.overall);
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.drawPath(
    cardOutline(size).shift(const Offset(0, 2)),
    Paint()
      ..color = MilanacColors.black.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
  CardFacePainter(design, glow: false).paint(canvas, size);

  // La foto della carta (o il volto) a destra, ritagliata con la sagoma.
  canvas.save();
  canvas.clipPath(cardOutline(size));
  final area = Rect.fromLTWH(
    _cardW * .30,
    _cardH * .05,
    _cardW * .66,
    _cardH * .55,
  );
  if (photo != null) {
    final src = Size(photo.width.toDouble(), photo.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, src, area.size);
    final dst = Alignment.bottomCenter.inscribe(fit.destination, area);
    canvas.drawImageRect(
      photo,
      Offset.zero & src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  } else if (m.face case final face?) {
    final side = area.height;
    canvas.save();
    canvas.translate(area.center.dx - side / 2, area.bottom - side);
    FacePainter(face).paint(canvas, Size(side, side));
    canvas.restore();
  }
  canvas.restore();

  // Overall (con il bonus) e ruolo in alto a sinistra, nome sulla carta in basso.
  _text(
    canvas,
    overallWith(m.overall, special)?.toString() ?? '–',
    const Offset(_cardW * .19, _cardH * .17),
    15,
    FontWeight.w700,
    design.text,
  );
  _text(
    canvas,
    label,
    const Offset(_cardW * .19, _cardH * .32),
    8,
    FontWeight.w600,
    design.text,
  );
  _text(
    canvas,
    m.displayName.toUpperCase(),
    const Offset(_cardW / 2, _cardH * .68),
    8.5,
    FontWeight.w600,
    design.text,
    maxWidth: _cardW - 10,
  );
  canvas.drawLine(
    const Offset(_cardW * .25, _cardH * .76),
    const Offset(_cardW * .75, _cardH * .76),
    Paint()
      ..strokeWidth = .7
      ..color = design.line.withValues(alpha: .7),
  );
  canvas.restore();
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
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Oswald-500.ttf'),
  );
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Oswald-400.ttf'),
  );
  final crest = pw.MemoryImage(
    (await rootBundle.load('assets/images/stemma_256.png')).buffer
        .asUint8List(),
  );
  final when = DateFormat(
    "EEEE d MMMM yyyy",
    'it',
  ).format(date ?? italianDay(DateTime.now()));
  final starters = [
    for (final (i, slot) in formation.slots.indexed)
      if (members[formation.players[i]] case final m?)
        '${slot.label} ${m.displayName}',
  ];
  // Sul foglio bianco i titoli sono in oro scuro, la riga in oro pieno.
  final title = PdfColor.fromInt(MilanacColors.goldDeep.toARGB32());
  final gold = PdfColor.fromInt(MilanacColors.gold.toARGB32());

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
                    style: pw.TextStyle(font: bold, fontSize: 22, color: title),
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
          pw.Center(child: pw.Image(pw.MemoryImage(image), height: 560)),
          pw.SizedBox(height: 12),
          pw.Text(
            'TITOLARI',
            style: pw.TextStyle(font: bold, fontSize: 12, color: title),
          ),
          pw.Text(
            starters.isEmpty ? 'Da definire' : starters.join(' · '),
            style: pw.TextStyle(font: regular, fontSize: 10),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'PANCHINA',
            style: pw.TextStyle(font: bold, fontSize: 12, color: title),
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

/// Disegna, impagina e condivide il PDF della formazione. [photoOf] carica la foto
/// della carta di un titolare (null se non c'è: si disegna il volto).
Future<void> shareFormationPdf(
  BuildContext context, {
  required Formation formation,
  required Map<String, Member> members,
  required List<Member> bench,
  Map<String, SpecialCard> specials = const {},
  Future<ui.Image?> Function(Member member)? photoOf,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final photos = <String, ui.Image>{};
  try {
    if (photoOf != null) {
      for (final id in formation.players.values) {
        final m = members[id];
        if (m == null || m.avatarPath == null) continue;
        final photo = await photoOf(m);
        if (photo != null) photos[m.id] = photo;
      }
    }
    final image = await renderFormationImage(
      formation,
      members,
      specials: specials,
      photos: photos,
    );
    final bytes = await buildFormationPdf(
      formation: formation,
      members: members,
      bench: bench,
      image: image,
      // Il giorno della pubblicazione in Italia.
      date: formation.publishedAt == null
          ? null
          : italianClock(formation.publishedAt!),
    );
    final day = DateFormat('yyyy-MM-dd').format(italianDay(DateTime.now()));
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
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e, action: 'PDF non creato'))),
    );
  } finally {
    for (final photo in photos.values) {
      photo.dispose();
    }
  }
}
