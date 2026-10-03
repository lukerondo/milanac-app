import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import 'intro_state.dart';

/// Intro: video del club (se presente in assets/video/intro.mp4, altrimenti immagine
/// di sfondo), stemma del Milano FC e barra di caricamento. Tocca per saltare.
class IntroPage extends ConsumerStatefulWidget {
  const IntroPage({super.key});

  static const videoAsset = 'assets/video/intro.mp4';
  static const fallbackDuration = Duration(milliseconds: 3500);

  @override
  ConsumerState<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends ConsumerState<IntroPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _video;
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress =
        AnimationController(vsync: this, duration: IntroPage.fallbackDuration)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) _finish();
          });
    _start();
  }

  Future<void> _start() async {
    if (await _hasVideo()) {
      final controller = VideoPlayerController.asset(IntroPage.videoAsset);
      try {
        await controller.initialize();
        await controller.setVolume(0);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() => _video = controller);
        _progress.duration = controller.value.duration;
        unawaited(controller.play());
      } catch (_) {
        await controller.dispose();
      }
    }
    if (mounted) unawaited(_progress.forward());
  }

  Future<bool> _hasVideo() async {
    try {
      await rootBundle.load(IntroPage.videoAsset);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _finish() => ref.read(introDoneProvider.notifier).complete();

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null && video.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              )
            else
              Image.asset('assets/images/intro_bg.png', fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [0.55, 1],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Stemma del Milano FC (versione non ufficiale di EA SPORTS FC 27),
                    // che compare in dissolvenza all'inizio del caricamento.
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _progress,
                        curve: const Interval(0, .2, curve: Curves.easeOut),
                      ),
                      child: Image.asset(
                        'assets/images/stemma_milano_fc.png',
                        height: 120,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) => Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: _progress.value,
                              minHeight: 8,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(
                                MilanacColors.red,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Caricamento… ${(_progress.value * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tocca per saltare',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
