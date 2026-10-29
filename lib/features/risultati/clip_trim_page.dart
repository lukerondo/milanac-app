import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/gold_loader.dart';
import 'clip_service.dart';
import 'media_viewer.dart' show mediaTheme;

/// Anteprima del video scelto: il Direttivo sceglie da dove iniziare,
/// l'app taglia 15 secondi e comprime il file prima di caricarlo.
class ClipTrimPage extends StatefulWidget {
  const ClipTrimPage({super.key, required this.path});
  final String path;

  @override
  State<ClipTrimPage> createState() => _ClipTrimPageState();
}

class _ClipTrimPageState extends State<ClipTrimPage> {
  late final VideoPlayerController _video = VideoPlayerController.file(
    File(widget.path),
  );
  double _start = 0;
  bool _processing = false;

  double get _total => _video.value.duration.inMilliseconds / 1000;
  double get _maxStart => (_total - maxClipSeconds).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    _video.initialize().then(
      (_) {
        if (!mounted) return;
        setState(() {});
        _video
          ..setLooping(false)
          ..play();
      },
      onError: (Object _) {
        // Formato che il telefono non sa leggere (codec, file danneggiato...):
        // si avvisa e si torna indietro invece di girare a vuoto.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossibile aprire questo video: prova con un altro file.',
            ),
          ),
        );
        Navigator.of(context).pop();
      },
    );
    _video.addListener(_loopWindow);
  }

  /// Riproduce in loop solo la finestra di 15 secondi selezionata.
  void _loopWindow() {
    if (!_video.value.isInitialized) return;
    final pos = _video.value.position.inMilliseconds / 1000;
    if (pos >= _start + maxClipSeconds || pos >= _total - 0.05) {
      _video.seekTo(Duration(milliseconds: (_start * 1000).round()));
    }
  }

  @override
  void dispose() {
    _video
      ..removeListener(_loopWindow)
      ..dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _processing = true);
    await _video.pause();
    try {
      final clip = await ClipService.prepare(
        widget.path,
        startS: _start.round(),
      );
      if (mounted) Navigator.of(context).pop(clip);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(e, action: 'Preparazione della clip non riuscita'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _video.value.isInitialized;
    final end = (_start + maxClipSeconds).clamp(0, ready ? _total : 0);
    // Il video si guarda su fondo nero, anche con il tema chiaro.
    return Theme(
      data: mediaTheme,
      child: Scaffold(
        backgroundColor: MilanacColors.black,
        appBar: AppBar(
          backgroundColor: MilanacColors.black,
          title: const Text('SCEGLI LA CLIP'),
        ),
        body: !ready
            ? const Center(child: GoldLoader())
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _video.value.aspectRatio,
                        child: VideoPlayer(_video),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Text(
                      _maxStart == 0
                          ? 'Il video dura ${_total.toStringAsFixed(0)}s: verrà caricato intero.'
                          : 'Clip da ${_start.toStringAsFixed(0)}s a ${end.toStringAsFixed(0)}s '
                                '(max $maxClipSeconds secondi)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_maxStart > 0)
                    Slider(
                      value: _start,
                      max: _maxStart,
                      onChanged: (v) {
                        setState(() => _start = v);
                        _video.seekTo(
                          Duration(milliseconds: (v * 1000).round()),
                        );
                      },
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _processing ? null : _confirm,
                          icon: _processing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: GoldLoader(size: 18),
                                )
                              : const Icon(Icons.content_cut_rounded),
                          label: Text(
                            _processing
                                ? 'Preparazione clip…'
                                : 'Taglia e carica',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
