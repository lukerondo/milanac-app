import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../shared/async_view.dart';
import 'match.dart';
import 'matches_repository.dart';

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

/// Visualizzatore a schermo intero per foto e clip.
class MediaViewer extends ConsumerStatefulWidget {
  const MediaViewer({super.key, required this.media});
  final MatchMedia media;

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer> {
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
    Widget body;
    if (widget.media.type == MediaType.photo) {
      body = InteractiveViewer(
        child: Center(child: MediaImage(media: widget.media)),
      );
    } else if (_error != null) {
      body = ErrorRetry(message: _error!, onRetry: _canRetry ? _retry : null);
    } else if (video == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = GestureDetector(
        onTap: () => setState(
          () => video.value.isPlaying ? video.pause() : video.play(),
        ),
        child: Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.media.caption ??
              (widget.media.type == MediaType.video ? 'CLIP' : 'FOTO'),
        ),
      ),
      body: body,
    );
  }
}
