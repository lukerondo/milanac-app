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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Riquadro di caricamento: stemma Milano FC (versione non ufficiale di
                    // EA SPORTS FC 27) e barra che si riempie in sincronia con il video.
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _progress,
                        curve: const Interval(0, .12, curve: Curves.easeOut),
                      ),
                      child: _LoadingPanel(progress: _progress),
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

/// Riquadro scuro arrotondato con lo stemma a sinistra e la barra di caricamento.
class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.progress});
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      decoration: BoxDecoration(
        color: const Color(0xE61C1C1F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/stemma_milano_fc.png',
            height: 64,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: AnimatedBuilder(
              animation: progress,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MILANAC PRO CLUB',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.value,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(
                        MilanacColors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Caricamento… ${(progress.value * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
