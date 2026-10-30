import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';

/// La foto della carta è 4:5, come il riquadro del ritratto sulla carta FUT.
const cardPhotoAspect = 4 / 5;
const cardPhotoSize = Size(720, 900);

/// Sceglie una foto dalla galleria e la fa inquadrare (sposta e allarga) nel riquadro
/// della carta: restituisce il JPEG 720×900 da caricare, null se si annulla.
Future<Uint8List?> pickCardPhoto(BuildContext context) async {
  final XFile? file;
  try {
    // Con le dimensioni massime il telefono la ricodifica in JPEG (anche le HEIC).
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 92,
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non riesco ad aprire la galleria. Riprova.'),
        ),
      );
    }
    return null;
  }
  if (file == null || !context.mounted) return null;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoFramePage(bytes: bytes),
    ),
  );
}

/// Inquadratura dell'immagine nel riquadro: [scale] pixel dello schermo per pixel della
/// foto, [offset] posizione dell'angolo in alto a sinistra della foto rispetto al
/// riquadro.
@immutable
class PhotoFraming {
  const PhotoFraming(this.scale, this.offset);
  final double scale;
  final Offset offset;

  /// La scala minima: la foto copre tutto il riquadro.
  static double coverScale(Size image, Size frame) =>
      math.max(frame.width / image.width, frame.height / image.height);

  /// All'inizio: foto che copre il riquadro, centrata in orizzontale e con la parte alta
  /// in vista (di solito il viso sta lì).
  factory PhotoFraming.initial(Size image, Size frame) {
    final s = coverScale(image, frame);
    return PhotoFraming(
      s,
      Offset(
        (frame.width - image.width * s) / 2,
        (frame.height - image.height * s) * .3,
      ),
    ).clamped(image, frame);
  }

  /// Tenuta dentro i limiti: mai spazi vuoti nel riquadro, al massimo 5 volte la
  /// copertura.
  PhotoFraming clamped(Size image, Size frame) {
    final min = coverScale(image, frame);
    final s = scale.clamp(min, min * 5).toDouble();
    final w = image.width * s, h = image.height * s;
    // Con la scala minima w può venire un'inezia più piccola del riquadro
    // (arrotondamento): il limite basso non deve mai superare lo zero.
    final minX = math.min(frame.width - w, 0.0);
    final minY = math.min(frame.height - h, 0.0);
    return PhotoFraming(
      s,
      Offset(
        offset.dx.clamp(minX, 0.0).toDouble(),
        offset.dy.clamp(minY, 0.0).toDouble(),
      ),
    );
  }

  /// Zoom di [factor] rispetto a [start] tenendo fermo il punto della foto che stava
  /// sotto [focalStart] e portandolo in [focal].
  static PhotoFraming zoom(
    PhotoFraming start,
    double factor,
    Offset focalStart,
    Offset focal,
    Size image,
    Size frame,
  ) {
    final point = (focalStart - start.offset) / start.scale;
    final s = (start.scale * factor)
        .clamp(coverScale(image, frame), coverScale(image, frame) * 5)
        .toDouble();
    return PhotoFraming(s, focal - point * s).clamped(image, frame);
  }

  /// La parte della foto (in pixel della foto) che sta nel riquadro.
  Rect source(Size frame) => Rect.fromLTWH(
    -offset.dx / scale,
    -offset.dy / scale,
    frame.width / scale,
    frame.height / scale,
  );
}

/// Ritaglia [source] da [image] e lo porta a 720×900 in JPEG.
Future<Uint8List> cropToJpeg(ui.Image image, Rect source) async {
  final recorder = ui.PictureRecorder();
  final out = Offset.zero & cardPhotoSize;
  Canvas(recorder).drawImageRect(
    image,
    source,
    out,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(
    cardPhotoSize.width.toInt(),
    cardPhotoSize.height.toInt(),
  );
  picture.dispose();
  final rgba = await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
  cropped.dispose();
  return compute(_encodeJpeg, rgba!.buffer.asUint8List());
}

Uint8List _encodeJpeg(Uint8List rgba) => img.encodeJpg(
  img.Image.fromBytes(
    width: cardPhotoSize.width.toInt(),
    height: cardPhotoSize.height.toInt(),
    bytes: rgba.buffer,
    numChannels: 4,
  ),
  quality: 85,
);

/// La foto scelta, da spostare e allargare dentro il riquadro della carta.
class PhotoFramePage extends StatefulWidget {
  const PhotoFramePage({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<PhotoFramePage> createState() => _PhotoFramePageState();
}

class _PhotoFramePageState extends State<PhotoFramePage> {
  ui.Image? _image;
  bool _failed = false;
  bool _saving = false;
  PhotoFraming? _framing;
  Size? _frame;
  PhotoFraming? _gestureStart;
  Offset _focalStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Size get _imageSize =>
      Size(_image!.width.toDouble(), _image!.height.toDouble());

  Future<void> _use() async {
    final image = _image, framing = _framing, frame = _frame;
    if (_saving || image == null || framing == null || frame == null) return;
    setState(() => _saving = true);
    try {
      final jpeg = await cropToJpeg(image, framing.source(frame));
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent) {
        Navigator.of(context).pop(jpeg);
      } else if (route.isActive) {
        // Nel frattempo si è aperto qualcos'altro sopra (il walkout di una carta
        // speciale): un pop chiuderebbe quello, quindi si toglie proprio questa pagina.
        Navigator.of(context).removeRoute(route, jpeg);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non riesco a preparare la foto. Riprova.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mentre prepara la foto non si esce (né con la X né con Indietro).
    return PopScope(canPop: !_saving, child: _scaffold(context));
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !_saving,
        title: const Text('INQUADRA LA FOTO'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: Text(
                'Trascina e allarga con due dita: viso e spalle dentro il '
                'riquadro, come sulla carta.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            Expanded(
              child: Center(
                child: _failed
                    ? const Text(
                        'Questa foto non si apre: scegline un\'altra.',
                        style: TextStyle(color: Colors.white),
                      )
                    : _image == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: AspectRatio(
                          aspectRatio: cardPhotoAspect,
                          child: LayoutBuilder(builder: _frameView),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MilanacColors.gold,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _image == null || _saving ? null : _use,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('Usa questa foto'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frameView(BuildContext context, BoxConstraints c) {
    final frame = Size(c.maxWidth, c.maxHeight);
    final image = _imageSize;
    if (_frame != frame || _framing == null) {
      // Primo disegno o schermo ruotato: si riparte dall'inquadratura iniziale.
      _framing = PhotoFraming.initial(image, frame);
      _frame = frame;
    }
    final f = _framing!;
    return GestureDetector(
      key: const ValueKey('inquadra-foto'),
      onScaleStart: (d) {
        _gestureStart = _framing;
        _focalStart = d.localFocalPoint;
      },
      onScaleUpdate: (d) {
        final start = _gestureStart;
        if (start == null) return;
        setState(
          () => _framing = PhotoFraming.zoom(
            start,
            d.scale,
            _focalStart,
            d.localFocalPoint,
            image,
            frame,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF111114)),
            Positioned(
              left: f.offset.dx,
              top: f.offset.dy,
              width: image.width * f.scale,
              height: image.height * f.scale,
              child: RawImage(image: _image, fit: BoxFit.fill),
            ),
            // Dove la carta sfuma la foto (il nome e le statistiche stanno lì sotto).
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x99000000)],
                    stops: [.72, 1],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MilanacColors.gold, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
