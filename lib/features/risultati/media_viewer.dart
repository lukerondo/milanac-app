import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'match.dart';
import 'matches_repository.dart';

/// URL firmato (valido 1 ora) per un file privato dello storage.
final mediaUrlProvider = FutureProvider.family<String, MatchMedia>(
  (ref, media) => ref.watch(matchesRepositoryProvider).mediaUrl(media),
);

/// Immagine di un media: da memoria (demo) o dallo storage tramite URL firmato.
class MediaImage extends ConsumerWidget {
  const MediaImage({super.key, required this.media, this.fit = BoxFit.contain});
  final MatchMedia media;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (media.localBytes != null) {
      return Image.memory(media.localBytes!, fit: fit);
    }
    final url = ref.watch(mediaUrlProvider(media));
    return url.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, _) => const Center(child: Icon(Icons.broken_image_rounded)),
      data: (u) => Image.network(
        u,
        fit: fit,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_rounded)),
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

  @override
  void initState() {
    super.initState();
    if (widget.media.type == MediaType.video) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final url = await ref.read(mediaUrlProvider(widget.media).future);
      if (url.isEmpty) {
        setState(
          () => _error = 'Anteprima video non disponibile in modalità demo.',
        );
        return;
      }
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
      await c.play();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossibile riprodurre la clip: $e');
      }
    }
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
      body = Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
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
