import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'fut_card.dart';

/// Dove sta la foto sulla carta grande (unità della carta da 300×420): la foto salvata
/// ha queste proporzioni, così sulla carta si vede esattamente come nell'anteprima.
const cardPortraitSize = Size(196, 226);

/// La foto salvata è disegnata a 3 volte la sua grandezza sulla carta (nitida anche
/// sui telefoni con lo schermo più fitto).
const _bakeScale = 3.0;

/// Lato lungo massimo della foto lavorata (più grande non serve e rallenta).
const _maxSide = 1100;

/// Scontorno: la persona senza lo sfondo.
abstract class PhotoCutout {
  /// true se su questo dispositivo lo scontorno automatico c'è.
  bool get available;

  /// La foto [image] con lo sfondo trasparente; null se non riesce (nessuna persona
  /// trovata, errore del riconoscimento).
  Future<ui.Image?> cutout(ui.Image image);
}

final photoCutoutProvider = Provider<PhotoCutout>(
  (ref) =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
      ? MlKitCutout()
      : const NoCutout(),
);

/// Web e computer: niente scontorno automatico (si può caricare un PNG già pronto).
class NoCutout implements PhotoCutout {
  const NoCutout();

  @override
  bool get available => false;

  @override
  Future<ui.Image?> cutout(ui.Image image) async => null;
}

/// Lo scontorno di Google ML Kit, sul telefono e senza server: riconosce la persona
/// e restituisce, per ogni punto, quanto è sicuro che sia lei.
class MlKitCutout implements PhotoCutout {
  @override
  bool get available => true;

  @override
  Future<ui.Image?> cutout(ui.Image image) async {
    // ML Kit legge un file: la foto (già rimpicciolita) va in un file temporaneo.
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}carta_'
      '${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single);
    try {
      final mask = await segmenter.processImage(
        InputImage.fromFilePath(file.path),
      );
      if (mask == null) return null;
      return await applyMask(image, mask.width, mask.height, mask.confidences);
    } catch (_) {
      return null;
    } finally {
      unawaited(segmenter.close().catchError((Object _) {}));
      unawaited(file.delete().then((_) {}, onError: (Object _) {}));
    }
  }
}

/// La foto con la trasparenza della maschera (bordi morbidi), ritagliata attorno alla
/// persona. null se nella maschera non c'è nessuno.
Future<ui.Image?> applyMask(
  ui.Image image,
  int maskWidth,
  int maskHeight,
  List<double> confidences,
) async {
  final w = image.width, h = image.height;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null || confidences.length < maskWidth * maskHeight) return null;
  final px = data.buffer.asUint8List();
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    final my = math.min(maskHeight - 1, y * maskHeight ~/ h);
    for (var x = 0; x < w; x++) {
      final mx = math.min(maskWidth - 1, x * maskWidth ~/ w);
      final c = confidences[my * maskWidth + mx];
      // Bordo morbido: sotto 0,35 è sfondo, sopra 0,75 è persona.
      final a = ((c - .35) / .40).clamp(0.0, 1.0);
      final i = (y * w + x) * 4;
      // I pixel sono "premoltiplicati": colore e trasparenza si scalano insieme.
      px[i] = (px[i] * a).round();
      px[i + 1] = (px[i + 1] * a).round();
      px[i + 2] = (px[i + 2] * a).round();
      px[i + 3] = (px[i + 3] * a).round();
      if (a > .1) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  // Troppo poco per essere una persona.
  if (maxX < 0 || (maxX - minX) * (maxY - minY) < w * h * .03) return null;
  // Margine attorno alla persona (più spazio sopra la testa); in basso si arriva al
  // bordo, la carta la sfuma.
  final padX = ((maxX - minX) * .06).round();
  final left = math.max(0, minX - padX);
  final right = math.min(w - 1, maxX + padX);
  final top = math.max(0, minY - ((maxY - minY) * .06).round());
  final cw = right - left + 1, ch = h - top;
  final cropped = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    final from = ((top + y) * w + left) * 4;
    cropped.setRange(y * cw * 4, (y + 1) * cw * 4, px, from);
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    cropped,
    cw,
    ch,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// true se la foto ha già lo sfondo trasparente (un PNG scontornato dal telefono).
Future<bool> hasTransparency(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return false;
  final px = data.buffer.asUint8List();
  var clear = 0;
  final total = image.width * image.height;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] < 250) clear++;
  }
  return clear > total * .02;
}

/// La foto come si vedrà sulla carta: dentro il riquadro del ritratto, appoggiata in
/// basso al centro, con l'ingrandimento [scale] (dal centro in basso) e lo spostamento
/// [offset] (unità della carta) scelti con le dita. PNG trasparente.
Future<Uint8List> bakePortrait(
  ui.Image photo,
  double scale,
  Offset offset,
) async {
  final w = cardPortraitSize.width * _bakeScale;
  final h = cardPortraitSize.height * _bakeScale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final src = Size(photo.width.toDouble(), photo.height.toDouble());
  final fit = applyBoxFit(BoxFit.contain, src, Size(w, h));
  final dst = Alignment.bottomCenter.inscribe(
    fit.destination,
    Offset.zero & Size(w, h),
  );
  canvas
    ..translate(offset.dx * _bakeScale, offset.dy * _bakeScale)
    ..translate(w / 2, h)
    ..scale(scale)
    ..translate(-w / 2, -h)
    ..drawImageRect(
      photo,
      Offset.zero & src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  final image = await recorder.endRecording().toImage(w.round(), h.round());
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// La scelta della foto: dalla galleria o dalla fotocamera del telefono (nei test una
/// foto finta). null se si annulla.
final cardPhotoPickerProvider =
    Provider<Future<Uint8List?> Function(ImageSource source)>(
      (ref) =>
          (source) async =>
              (await ImagePicker().pickImage(source: source))?.readAsBytes(),
    );

/// Apre la pagina della foto della carta (solo per la propria).
Future<void> showCardPhotoEditor(BuildContext context, Member member) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'foto-carta'),
        builder: (_) => CardPhotoPage(member: member),
      ),
    );

/// La foto della carta: si sceglie (o si scatta), l'app toglie lo sfondo, la si sposta e
/// ingrandisce con le dita guardando la carta vera, poi si salva. Si può anche togliere
/// e tornare al volto disegnato.
class CardPhotoPage extends ConsumerStatefulWidget {
  const CardPhotoPage({super.key, required this.member});
  final Member member;

  @override
  ConsumerState<CardPhotoPage> createState() => _CardPhotoPageState();
}

enum _Step { scegli, lavora, sistema, salva }

class _CardPhotoPageState extends ConsumerState<CardPhotoPage> {
  var _step = _Step.scegli;

  /// La foto scelta (scontornata se possibile) e l'anteprima sulla carta.
  ui.Image? _photo;
  Uint8List? _preview;
  bool _cutDone = false;
  double _scale = 1;
  double _baseScale = 1;
  Offset _offset = Offset.zero;

  /// Larghezza della carta sullo schermo (per convertire i movimenti delle dita).
  double _cardWidth = 280;

  @override
  void dispose() {
    _photo?.dispose();
    super.dispose();
  }

  Future<void> _choose(ImageSource source) async {
    final Uint8List? bytes;
    try {
      bytes = await ref.read(cardPhotoPickerProvider)(source);
    } catch (e) {
      _notice(friendlyError(e, action: 'Foto non caricata'));
      return;
    }
    if (bytes == null || !mounted) return;
    setState(() => _step = _Step.lavora);
    try {
      // Rimpicciolita subito: lo scontorno e il salvataggio vanno più veloci.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final long = math.max(descriptor.width, descriptor.height);
      final factor = long > _maxSide ? _maxSide / long : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * factor).round(),
        targetHeight: (descriptor.height * factor).round(),
      );
      final small = (await codec.getNextFrame()).image;
      var photo = small;
      var cut = await hasTransparency(small);
      if (!cut) {
        final cutout = await ref.read(photoCutoutProvider).cutout(small);
        if (cutout != null) {
          photo = cutout;
          cut = true;
          small.dispose();
        }
      }
      if (!mounted) {
        photo.dispose();
        return;
      }
      _photo?.dispose();
      _photo = photo;
      _cutDone = cut;
      _scale = 1;
      _offset = Offset.zero;
      await _refreshPreview();
      if (mounted) setState(() => _step = _Step.sistema);
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.scegli);
      _notice(friendlyError(e, action: 'Foto non letta'));
    }
  }

  Future<void> _refreshPreview() async {
    final photo = _photo;
    if (photo == null) return;
    final png = await bakePortrait(photo, _scale, _offset);
    if (mounted) setState(() => _preview = png);
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() => _step = _Step.salva);
    try {
      final png = await bakePortrait(photo, _scale, _offset);
      await ref
          .read(rosaRepositoryProvider)
          .uploadPhoto(widget.member, png, contentType: 'image/png');
      if (!mounted) return;
      _notice('Foto salvata sulla tua carta.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.sistema);
      _notice(friendlyError(e, action: 'Foto non salvata'));
    }
  }

  Future<void> _remove() async {
    setState(() => _step = _Step.salva);
    try {
      await ref.read(rosaRepositoryProvider).removePhoto(widget.member);
      if (!mounted) return;
      _notice('Foto tolta: sulla carta torna il tuo volto.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.scegli);
      _notice(friendlyError(e, action: 'Foto non tolta'));
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final member =
        ref
            .watch(rosaProvider)
            .value
            ?.where((m) => m.id == widget.member.id)
            .firstOrNull ??
        widget.member;
    final special = ref.watch(activeSpecialCardProvider(member.id));
    final preview = _preview;
    final editing = _step == _Step.sistema && preview != null;
    final busy = _step == _Step.lavora || _step == _Step.salva;
    final cutAvailable = ref.watch(photoCutoutProvider).available;
    return Scaffold(
      appBar: AppBar(title: const Text('FOTO DELLA CARTA')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: LayoutBuilder(
              builder: (context, box) {
                _cardWidth = math.min(280, box.maxWidth);
                final card = SizedBox(
                  width: _cardWidth,
                  child: FutCard(
                    member: member,
                    special: special?.kind,
                    bonus: special?.bonus ?? 0,
                    previewPhoto: preview == null ? null : MemoryImage(preview),
                  ),
                );
                if (!editing) return card;
                // Con le dita: si sposta e si ingrandisce la foto sulla carta.
                final unit = FutCard.width / _cardWidth;
                return GestureDetector(
                  onScaleStart: (_) => _baseScale = _scale,
                  onScaleUpdate: (d) => setState(() {
                    _scale = (_baseScale * d.scale).clamp(.6, 2.2);
                    _offset += d.focalPointDelta * unit;
                  }),
                  onScaleEnd: (_) => _refreshPreview(),
                  child: card,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (busy)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _step == _Step.lavora
                        ? 'Tolgo lo sfondo dalla foto…'
                        : 'Salvo…',
                    style: TextStyle(fontSize: 15, color: p.textSecondary),
                  ),
                ),
              ],
            )
          else if (editing) ...[
            Text(
              _cutDone
                  ? 'Sfondo tolto. Trascina per spostarti, avvicina o '
                        'allontana due dita per ingrandire.'
                  : 'Qui lo sfondo non si toglie da solo: la foto si vedrà '
                        'intera, sfumata in basso. Trascina e ingrandisci con le '
                        'dita.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.35, color: p.text),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.zoom_out_rounded, size: 20),
                Expanded(
                  child: Slider(
                    value: _scale,
                    min: .6,
                    max: 2.2,
                    label: 'Grandezza',
                    semanticFormatterCallback: (v) =>
                        'Grandezza ${(v * 100).round()}%',
                    onChanged: (v) => setState(() => _scale = v),
                    onChangeEnd: (_) => _refreshPreview(),
                  ),
                ),
                const Icon(Icons.zoom_in_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salva sulla carta'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _photo?.dispose();
                _photo = null;
                _preview = null;
                _step = _Step.scegli;
              }),
              child: const Text('Scegli un\'altra foto'),
            ),
          ] else ...[
            AppCard(
              child: Text(
                cutAvailable
                    ? 'Scegli una foto a mezzo busto, con la luce davanti e uno '
                          'sfondo semplice: l\'app toglie lo sfondo da sola, come '
                          'nelle carte di FC.'
                    : 'Carica una foto già scontornata (PNG senza sfondo: sul '
                          'telefono tieni premuta la persona nella Galleria o in '
                          'Foto e copiala), oppure una foto normale: si vedrà '
                          'sfumata in basso.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: p.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _choose(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Scegli una foto'),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _choose(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Scatta una foto'),
              ),
            ],
            if (member.avatarPath != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Togli la foto (torna il volto)'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
