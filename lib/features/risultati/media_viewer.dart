import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../shared/async_view.dart';
import 'match.dart';
import 'matches_repository.dart';

/// Tema scuro delle pagine che mostrano foto e video (sempre su fondo nero).
final mediaTheme = buildTheme(Brightness.dark);

/// URL firmato per un file privato dello storage. Vale un'ora: si riusa per 50 minuti,
/// poi (quando nessuno lo mostra più) se ne chiede uno nuovo.
final mediaUrlProvider = FutureProvider.autoDispose.family<String, MatchMedia>((
  ref,
  media,
) async {
  final keep = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 50), keep.close);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(matchesRepositoryProvider).mediaUrl(media);
  } catch (_) {
    keep.close(); // un errore non resta in memoria
    rethrow;
  }
});

/// Immagine di un media: da memoria (demo) o dallo storage tramite URL firmato.
class MediaImage extends ConsumerStatefulWidget {
  const MediaImage({super.key, required this.media, this.fit = BoxFit.contain});
  final MatchMedia media;
  final BoxFit fit;

  @override
  ConsumerState<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends ConsumerState<MediaImage> {
  /// L'URL rifiutato (di solito scaduto) si rigenera una volta sola.
  bool _renewed = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media.localBytes != null) {
      return Image.memory(media.localBytes!, fit: widget.fit);
    }
    const broken = Center(child: Icon(Icons.broken_image_rounded));
    final url = ref.watch(mediaUrlProvider(media));
    return url.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, _) => broken,
      data: (u) => Image.network(
        u,
        fit: widget.fit,
        errorBuilder: (_, _, _) {
          if (!_renewed) {
            _renewed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) ref.invalidate(mediaUrlProvider(media));
            });
          }
          return broken;
        },
      ),
    );
  }
}

/// Foto e clip della partita a tutto schermo, una dopo l'altra scorrendo di lato: la
/// clip parte da sola e si ferma uscendo dalla sua pagina.
class MediaGallery extends StatefulWidget {
  const MediaGallery({super.key, required this.items, this.initial = 0});
  final List<MatchMedia> items;
  final int initial;

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.items[_index];
    final count = widget.items.length;
    // Foto e clip si guardano su fondo nero, anche con il tema chiaro.
    return Theme(
      data: mediaTheme,
      child: Scaffold(
        backgroundColor: MilanacColors.black,
        appBar: AppBar(
          backgroundColor: MilanacColors.black,
          title: Text(
            media.caption ?? (media.type == MediaType.video ? 'CLIP' : 'FOTO'),
          ),
          actions: [
            if (count > 1)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '${_index + 1} / $count',
                    style: const TextStyle(
                      fontFamily: sportFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: PageView.builder(
          controller: _pages,
          itemCount: count,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => _MediaPage(media: widget.items[i]),
        ),
      ),
    );
  }
}

/// Una foto (da ingrandire con due dita) o una clip (tocco = pausa / riprendi).
class _MediaPage extends ConsumerStatefulWidget {
  const _MediaPage({required this.media});
  final MatchMedia media;

  @override
  ConsumerState<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<_MediaPage> {
  VideoPlayerController? _video;
  String? _error;
  bool _canRetry = false;

  @override
  void initState() {
    super.initState();
    if (widget.media.type == MediaType.video) _initVideo();
  }

  Future<void> _initVideo() async {
    VideoPlayerController? c;
    try {
      // URL nuovo a ogni apertura: quello firmato vale solo un'ora.
      final url = await ref
          .read(matchesRepositoryProvider)
          .mediaUrl(widget.media);
      if (url.isEmpty) {
        if (mounted) {
          setState(
            () => _error = 'Anteprima video non disponibile in modalità demo.',
          );
        }
        return;
      }
      c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
      await c.play();
    } catch (_) {
      // Il lettore che non è partito va liberato (decoder e connessione).
      if (c != null && !identical(c, _video)) await c.dispose();
      if (mounted) {
        setState(() {
          _error = 'Impossibile riprodurre la clip.';
          _canRetry = true;
        });
      }
    }
  }

  void _retry() {
    final old = _video;
    setState(() {
      _video = null;
      _error = null;
      _canRetry = false;
    });
    old?.dispose();
    _initVideo();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    if (widget.media.type == MediaType.photo) {
      return InteractiveViewer(
        child: Center(child: MediaImage(media: widget.media)),
      );
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _canRetry ? _retry : null);
    }
    if (video == null) return const Center(child: CircularProgressIndicator());
    // Il lettore si ridisegna da solo quando parte o si ferma: niente setState
    // (che non accetta una funzione che restituisce un Future).
    return GestureDetector(
      onTap: () => video.value.isPlaying ? video.pause() : video.play(),
      child: Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: VideoPlayer(video),
        ),
      ),
    );
  }
}
