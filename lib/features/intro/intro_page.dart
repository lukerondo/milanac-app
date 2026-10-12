import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import 'intro_state.dart';

/// Intro: video del club (assets/video/intro.mp4; se manca, sfondo nero), stemma del Milano FC e barra di caricamento. Tocca per saltare.
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
    // Build senza configurazione: l'intro resta ferma sull'errore.
    if (!AppConfig.isMisconfigured) _start();
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

  void _finish() {
    if (AppConfig.isMisconfigured) return;
    ref.read(introDoneProvider.notifier).complete();
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.isMisconfigured) return const _ConfigError();
    final video = _video;
    // Intro finita (o saltata) ma la pagina è ancora qui: si aspetta il profilo dal
    // server, il router prosegue da solo appena arriva.
    final waiting = ref.watch(introDoneProvider);
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
              ),
            // Finché il video non è pronto (o se manca) lo sfondo resta nero:
            // nessuna immagine intermedia.
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
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: waiting ? null : _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        disabledForegroundColor: Colors.white70,
                        minimumSize: const Size(120, 44),
                      ),
                      icon: waiting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            )
                          : const Icon(Icons.skip_next_rounded),
                      label: Text(
                        waiting ? 'UN ATTIMO…' : 'SALTA',
                        style: const TextStyle(
                          fontFamily: sportFont,
                          fontSize: 15,
                          letterSpacing: 2,
                        ),
                      ),
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

/// Build di release compilata senza le chiavi del server: niente demo, solo l'errore.
class _ConfigError extends StatelessWidget {
  const _ConfigError();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/stemma_256.png', height: 96),
              const SizedBox(height: 20),
              const Text(
                'APP NON CONFIGURATA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: sportFont,
                  fontSize: 20,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Questa versione è stata compilata senza il collegamento al server '
                'del club (manca env/prod.json). Installa la versione ufficiale.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
            'assets/images/stemma_256.png',
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
                      fontFamily: sportFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      letterSpacing: 2,
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
