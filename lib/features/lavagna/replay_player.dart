import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme.dart';
import '../chat/voice_player.dart' show formatSeconds;
import 'board_model.dart';
import 'board_painter.dart';

/// Riproduce un replay: la voce (se c'è) e le mosse sulla lavagna, sincronizzate.
/// Senza audio (demo) va avanti un orologio interno.
class ReplayPlayer extends ChangeNotifier {
  ReplayPlayer(this.data, {this.audioUrl, this.audioFile});

  final ReplayData data;
  final String? audioUrl;
  final String? audioFile;

  AudioPlayer? _audio;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _clock;
  int positionMs = 0;
  bool playing = false;
  bool _audioFailed = false;
  bool _disposed = false;

  // Stato della lavagna aggiornato in modo incrementale.
  late BoardEditor _editor = BoardEditor(data.initial);
  int _cursor = 0;

  int get durationMs => data.durationMs;
  bool get hasAudio => (audioUrl != null || audioFile != null) && !_audioFailed;

  /// La lavagna all'istante corrente.
  BoardState get state => _editor.state;

  void _goTo(int ms) {
    final target = ms.clamp(0, durationMs);
    if (target < positionMs || _cursor > data.events.length) {
      _editor = BoardEditor(data.initial);
      _cursor = 0;
    }
    while (_cursor < data.events.length && data.events[_cursor].t <= target) {
      _editor.apply(data.events[_cursor].command);
      _cursor++;
    }
    positionMs = target;
    notifyListeners();
  }

  Future<AudioPlayer?> _ensureAudio() async {
    if (!hasAudio) return null;
    if (_audio != null) return _audio;
    final p = AudioPlayer();
    try {
      if (audioFile != null) {
        await p.setFilePath(audioFile!);
      } else {
        await p.setUrl(audioUrl!);
      }
    } catch (_) {
      _audioFailed = true;
      await p.dispose();
      return null;
    }
    _subs
      ..add(p.positionStream.listen((pos) {
        if (playing) _goTo(pos.inMilliseconds);
      }))
      ..add(p.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) _finish();
      }));
    return _audio = p;
  }

  void _finish() {
    playing = false;
    _clock?.cancel();
    _goTo(durationMs);
  }

  Future<void> play() async {
    if (playing || _disposed) return;
    if (positionMs >= durationMs) _goTo(0);
    playing = true;
    notifyListeners();
    final audio = await _ensureAudio();
    if (audio != null) {
      await audio.seek(Duration(milliseconds: positionMs));
      unawaited(audio.play());
      return;
    }
    // Senza audio: orologio interno a 20 fotogrammi al secondo.
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final ms = positionMs + 50;
      if (ms >= durationMs) {
        _finish();
      } else {
        _goTo(ms);
      }
    });
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _clock?.cancel();
    await _audio?.pause();
    notifyListeners();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> seek(int ms) async {
    _goTo(ms);
    if (_audio != null) await _audio!.seek(Duration(milliseconds: positionMs));
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _audio?.dispose();
    super.dispose();
  }
}

/// Lavagna animata con i controlli (ascolta/pausa, barra, tempi).
class ReplayView extends StatelessWidget {
  const ReplayView({super.key, required this.player, this.showNames = true});
  final ReplayPlayer player;
  final bool showNames;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: player,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: boardAspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: BoardPainter(player.state, showNames: showNames),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filled(
              tooltip: player.playing ? 'Pausa' : 'Play',
              style: IconButton.styleFrom(backgroundColor: MilanacColors.red),
              onPressed: player.toggle,
              icon: Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: Slider(
                value: player.positionMs
                    .clamp(0, player.durationMs)
                    .toDouble(),
                max: player.durationMs.toDouble().clamp(1, double.infinity),
                onChanged: (v) => player.seek(v.round()),
              ),
            ),
            Text(
              '${formatSeconds(player.positionMs ~/ 1000)} / '
              '${formatSeconds(player.durationMs ~/ 1000)}',
              style: const TextStyle(
                fontFamily: sportFont,
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        if (!player.hasAudio)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Senza audio',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
      ],
    ),
  );
}
