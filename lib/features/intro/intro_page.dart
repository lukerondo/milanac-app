import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/config.dart';
import '../../core/local_flags.dart';
import '../../core/theme.dart';
import '../../shared/gold_loader.dart';
import 'intro_state.dart';

/// Intro: video del club (assets/video/intro.mp4; se manca, sfondo nero) con i cori e
/// lo speaker, stemma del Milano FC, barra di caricamento in oro e "Milano siamo noi".
/// Tocca per saltare; l'audio si spegne (e resta spento) con il pulsante accanto a
/// "Salta".
class IntroPage extends ConsumerStatefulWidget {
  const IntroPage({super.key});

  static const videoAsset = 'assets/video/intro.mp4';
  static const fallbackDuration = Duration(milliseconds: 3500);

  /// Preferenza salvata sul telefono: "1" se l'audio dell'intro è spento.
  static const mutedFlag = 'intro_audio_spento';

  @override
  ConsumerState<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends ConsumerState<IntroPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _video;
  late final AnimationController _progress;

  /// Nel browser parte senza audio: i browser bloccano i video con l'audio che partono
  /// da soli.
  bool _muted = kIsWeb;

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
    final flags = ref.read(localFlagsProvider);
    try {
      if (await flags.getString(IntroPage.mutedFlag) == '1') _muted = true;
    } catch (_) {}
    if (mounted) setState(() {});
    if (await _hasVideo()) {
      final controller = VideoPlayerController.asset(IntroPage.videoAsset);
      try {
        await controller.initialize();
        await controller.setVolume(_muted ? 0 : 1);
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
    // Saltata: i cori si zittiscono (può partire la musica dell'app).
    unawaited(_video?.setVolume(0));
    ref.read(introDoneProvider.notifier).complete();
  }

  void _toggleAudio() {
    setState(() => _muted = !_muted);
    if (!ref.read(introDoneProvider)) {
      unawaited(_video?.setVolume(_muted ? 0 : 1));
    }
    unawaited(
      ref
          .read(localFlagsProvider)
          .setString(IntroPage.mutedFlag, _muted ? '1' : '0')
          .catchError((_) {}),
    );
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
      backgroundColor: MilanacColors.black,
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
            // Finché il video non è pronto (o se manca) lo sfondo resta nero; in basso
            // una sfumatura scura sotto stemma, barra e motto.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 280,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MilanacColors.black.withValues(alpha: 0),
                      MilanacColors.black.withValues(alpha: .9),
                    ],
                    stops: const [0, .72],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    right: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AudioButton(muted: _muted, onPressed: _toggleAudio),
                        const SizedBox(width: 10),
                        _SkipButton(
                          waiting: waiting,
                          onPressed: waiting ? null : _finish,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 32,
                    right: 32,
                    bottom: 40,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Stemma Milano FC (versione non ufficiale di EA SPORTS FC 27).
                        FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _progress,
                            curve: const Interval(
                              0,
                              .12,
                              curve: Curves.easeOut,
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/stemma_256.png',
                            height: 96,
                            filterQuality: FilterQuality.high,
                            semanticLabel: 'Stemma MILANAC Pro Club',
                          ),
                        ),
                        const SizedBox(height: 24),
                        _GoldProgress(progress: _progress),
                        const SizedBox(height: 14),
                        const Text(
                          'MILANO SIAMO NOI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: sportFont,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            letterSpacing: 3.3,
                            color: MilanacColors.goldLight,
                          ),
                        ),
                      ],
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
}

/// Audio dell'intro acceso o spento, accanto a "Salta".
class _AudioButton extends StatelessWidget {
  const _AudioButton({required this.muted, required this.onPressed});
  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: muted ? 'Accendi l\'audio' : 'Spegni l\'audio',
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      backgroundColor: MilanacColors.black.withValues(alpha: .55),
      foregroundColor: MilanacColors.ivory,
      side: BorderSide(color: MilanacColors.goldLight.withValues(alpha: .7)),
    ),
    icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
  );
}

/// "Salta" in alto a destra; finita l'intro, l'attesa del profilo.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.waiting, required this.onPressed});
  final bool waiting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      backgroundColor: MilanacColors.black.withValues(alpha: .55),
      foregroundColor: MilanacColors.ivory,
      disabledForegroundColor: MilanacColors.ivory,
      side: BorderSide(color: MilanacColors.goldLight.withValues(alpha: .7)),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (waiting) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: GoldLoader(size: 16, color: MilanacColors.goldLight),
          ),
          const SizedBox(width: 10),
        ],
        Text(waiting ? 'Un attimo…' : 'Salta'),
      ],
    ),
  );
}

/// Barra di caricamento sottile, in oro, che si riempie con il video.
class _GoldProgress extends StatelessWidget {
  const _GoldProgress({required this.progress});
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, _) => Semantics(
      label: 'Caricamento',
      value: '${(progress.value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: MilanacColors.ivory.withValues(alpha: .22)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.value.clamp(0, 1),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [MilanacColors.goldDeep, MilanacColors.goldLight],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Build di release compilata senza le chiavi del server: niente demo, solo l'errore.
class _ConfigError extends StatelessWidget {
  const _ConfigError();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MilanacColors.black,
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
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  letterSpacing: 1.5,
                  color: MilanacColors.goldLight,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Questa versione è stata compilata senza il collegamento al server '
                'del club (manca env/prod.json). Installa la versione ufficiale.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MilanacColors.ivoryMuted,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
