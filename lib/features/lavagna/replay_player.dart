import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/audio_focus.dart';
import '../../core/theme.dart';
import '../chat/voice_player.dart' show formatSeconds;
import 'board_model.dart';
import 'board_painter.dart';

/// Lascia l'audio quando una pagina si chiude: si aspetta la fine dello smontaggio
/// dei widget, durante il quale i provider non si possono cambiare.
void releaseAudioLater(AudioFocus? focus, AudioUse use) {
  if (focus == null) return;
  scheduleMicrotask(() {
    try {
      focus.release(use);
    } catch (_) {
      // App già chiusa: non c'è più niente da lasciare.
    }
  });
}

/// Riproduce un replay: la voce (se c'è) e le mosse sulla lavagna, sincronizzate.
/// Senza audio (demo) va avanti un orologio interno.
class ReplayPlayer extends ChangeNotifier
    implements ValueListenable<BoardState> {
  ReplayPlayer(this.data, {this.audioUrl, this.audioFile, this.focus})
    : _editor = BoardEditor(data.initial);

  final ReplayData data;
  final String? audioUrl;
  final String? audioFile;

  /// Audio coordinato: chi guarda un replay ferma gli altri lettori (e la musica).
  /// La pagina che lo mostra lo mette in pausa quando un altro prende l'audio.
  final AudioFocus? focus;

  AudioPlayer? _audio;
  Future<AudioPlayer?>? _audioLoad;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _clock;
  int positionMs = 0;
  bool playing = false;
  bool _audioFailed = false;
  bool _disposed = false;

  /// Cresce a ogni avvio, pausa e fine: un avvio rimasto in attesa (l'audio che si
  /// carica) non fa partire niente se nel frattempo si è messo in pausa o chiuso.
  int _run = 0;

  /// Passo dell'orologio interno (40 al secondo).
  static const _frame = Duration(milliseconds: 25);

  // Stato della lavagna aggiornato in modo incrementale.
  BoardEditor _editor;
  int _cursor = 0;

  int get durationMs => data.durationMs;
  bool get hasAudio => (audioUrl != null || audioFile != null) && !_audioFailed;

  /// La lavagna all'istante corrente.
  BoardState get state => _editor.state;

  @override
  BoardState get value => _editor.state;

  void _goTo(int ms) {
    if (_disposed) return;
    final target = ms.clamp(0, durationMs);
    if (target < positionMs) {
      _editor.dispose();
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

  Future<AudioPlayer?> _ensureAudio() {
    if (!hasAudio) return Future.value();
    // Un solo lettore anche con play, pausa, play mentre l'audio si carica.
    return _audioLoad ??= _loadAudio();
  }

  Future<AudioPlayer?> _loadAudio() async {
    final p = AudioPlayer();
    try {
      if (audioFile != null) {
        await p.setFilePath(audioFile!);
      } else {
        await p.setUrl(audioUrl!);
      }
    } catch (_) {
      unawaited(_quietly(p.dispose()));
      if (!_disposed) {
        _audioFailed = true;
        notifyListeners();
      }
      return null;
    }
    if (_disposed) {
      // Pagina chiusa mentre l'audio si caricava: il lettore non deve restare vivo
      // (né partire da solo).
      unawaited(_quietly(p.dispose()));
      return null;
    }
    _subs
      // La posizione 30-60 volte al secondo anche per i replay lunghi (quella di
      // serie arriva ogni 200 ms oltre i 160 secondi: gettoni a scatti).
      ..add(
        p
            .createPositionStream(
              minPeriod: const Duration(milliseconds: 16),
              maxPeriod: const Duration(milliseconds: 33),
            )
            .listen((pos) {
              if (playing) _goTo(pos.inMilliseconds);
            }),
      )
      ..add(
        p.playerStateStream.listen((s) {
          if (playing && s.processingState == ProcessingState.completed) {
            _finish();
          }
        }, onError: (Object _) => _halt()),
      );
    return _audio = p;
  }

  /// Fine del replay: tutte le mosse sulla lavagna e l'audio fermo (a fine brano
  /// just_audio resta "in riproduzione": spostando la barra ripartirebbe da solo).
  void _finish() {
    _halt();
    _goTo(durationMs);
  }

  /// Ferma tutto (pausa, fine, errore dell'audio) e lascia l'audio agli altri.
  void _halt() {
    _run++;
    _clock?.cancel();
    final audio = _audio;
    if (audio != null) unawaited(_quietly(audio.pause()));
    if (!playing) return;
    playing = false;
    focus?.release(AudioUse.replay);
    if (!_disposed) notifyListeners();
  }

  Future<void> play() async {
    if (playing || _disposed) return;
    final run = ++_run;
    if (positionMs >= durationMs) _goTo(0);
    playing = true;
    focus?.claim(AudioUse.replay);
    notifyListeners();
    final audio = await _ensureAudio();
    // Chiuso o messo in pausa mentre l'audio si caricava.
    if (_disposed || run != _run) return;
    if (audio == null) {
      _startClock();
      return;
    }
    try {
      await audio.seek(Duration(milliseconds: positionMs));
      if (_disposed || run != _run) return;
      unawaited(
        audio.play().catchError((Object _) {
          if (run == _run) _halt();
        }),
      );
    } catch (_) {
      if (run == _run) _halt();
    }
  }

  /// Senza audio: l'orologio conta i passi trascorsi, anche quelli saltati se l'app
  /// era occupata, quindi non accumula ritardo.
  void _startClock() {
    _clock?.cancel();
    final from = positionMs;
    _clock = Timer.periodic(_frame, (t) {
      final ms = from + t.tick * _frame.inMilliseconds;
      if (ms >= durationMs) {
        _finish();
      } else {
        _goTo(ms);
      }
    });
  }

  Future<void> pause() async {
    if (!playing) return;
    _halt();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> seek(int ms) async {
    _goTo(ms);
    if (_disposed) return;
    // Senza audio l'orologio riparte dal nuovo punto (se l'audio si sta ancora
    // caricando, partirà da qui).
    if (_clock?.isActive ?? false) _startClock();
    final audio = _audio;
    if (audio == null) return;
    try {
      await audio.seek(Duration(milliseconds: positionMs));
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _clock?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    final audio = _audio;
    if (audio != null) unawaited(_quietly(audio.dispose()));
    if (playing) {
      playing = false;
      releaseAudioLater(focus, AudioUse.replay);
    }
    _editor.dispose();
    super.dispose();
  }

  static Future<void> _quietly(Future<void> f) async {
    try {
      await f;
    } catch (_) {}
  }
}

/// Lavagna animata con i controlli (ascolta/pausa, barra, tempi).
class ReplayView extends StatelessWidget {
  const ReplayView({super.key, required this.player, this.showNames = true});
  final ReplayPlayer player;
  final bool showNames;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: boardAspect,
        // Si ridisegna da sola a ogni mossa; sotto si ricostruiscono solo i controlli.
        child: PitchFrame(
          child: BoardCanvas(board: player, showNames: showNames),
        ),
      ),
      const SizedBox(height: 10),
      ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final p = context.pal;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Ascoltare è l'azione principale della pagina: in oro pieno.
                  IconButton.filled(
                    tooltip: player.playing ? 'Pausa' : 'Play',
                    style: IconButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: player.toggle,
                    icon: Icon(
                      player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 28,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: player.positionMs
                          .clamp(0, player.durationMs)
                          .toDouble(),
                      max: player.durationMs.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: (v) => player.seek(v.round()),
                    ),
                  ),
                  Text(
                    '${formatSeconds(player.positionMs ~/ 1000)} / '
                    '${formatSeconds(player.durationMs ~/ 1000)}',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .4,
                      color: p.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              if (!player.hasAudio)
                Text(
                  'Senza audio',
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
            ],
          );
        },
      ),
    ],
  );
}
