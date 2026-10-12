import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/audio_focus.dart';

/// Stato della riproduzione dei vocali: un solo messaggio alla volta.
class VoiceState {
  const VoiceState({
    this.playingId,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
  });

  /// Messaggio caricato nel lettore (in riproduzione o in pausa).
  final String? playingId;
  final bool playing;
  final Duration position;
  final Duration? duration;

  /// Avanzamento 0..1 del messaggio caricato.
  double get progress {
    final d = duration;
    if (d == null || d.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0, 1).toDouble();
  }

  VoiceState copyWith({
    String? playingId,
    bool? playing,
    Duration? position,
    Duration? duration,
  }) => VoiceState(
    playingId: playingId ?? this.playingId,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );
}

/// Crea il lettore dei vocali (nei test se ne usa uno finto).
final voiceAudioPlayerFactoryProvider = Provider<AudioPlayer Function()>(
  (ref) => AudioPlayer.new,
);

/// Lettore condiviso dei messaggi vocali (just_audio), creato al primo ascolto.
/// Mentre suona tiene l'audio dell'app ([AudioUse.vocale]): la musica di sottofondo
/// aspetta, e se un altro audio prende il posto il vocale va in pausa.
class VoicePlayer extends Notifier<VoiceState> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];
  bool _wasPlaying = false;

  @override
  VoiceState build() {
    ref.listen(audioFocusProvider, (_, uses) {
      final p = _player;
      if (p != null && p.playing && !uses.contains(AudioUse.vocale)) {
        unawaited(p.pause());
      }
    });
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
      _player?.dispose();
      _player = null;
    });
    return const VoiceState();
  }

  AudioFocus get _focus => ref.read(audioFocusProvider.notifier);

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = ref.read(voiceAudioPlayerFactoryProvider)();
    _subs
      ..add(
        p.positionStream.listen((pos) => state = state.copyWith(position: pos)),
      )
      ..add(p.durationStream.listen((d) => state = state.copyWith(duration: d)))
      ..add(
        p.playerStateStream.listen(
          (s) {
            final completed = s.processingState == ProcessingState.completed;
            if (completed) {
              p.pause();
              p.seek(Duration.zero);
              state = state.copyWith(playing: false, position: Duration.zero);
            } else {
              state = state.copyWith(playing: s.playing);
            }
            // Finito o in pausa (anche dal sistema): l'audio dell'app torna libero.
            final playing = s.playing && !completed;
            if (_wasPlaying && !playing) _focus.release(AudioUse.vocale);
            _wasPlaying = playing;
          },
          // Riproduzione interrotta da un errore: si torna da capo.
          onError: (Object _) => _reset(),
        ),
      );
    return _player = p;
  }

  void _reset() {
    if (!ref.mounted) return;
    state = const VoiceState();
    _focus.release(AudioUse.vocale);
  }

  void _play(AudioPlayer p) {
    _focus.claim(AudioUse.vocale);
    unawaited(p.play().catchError((Object _) => _reset()));
  }

  /// Ascolta il vocale [id] (indirizzo [url]); se è già caricato, pausa/riprendi.
  /// Se non si carica lancia l'errore e il lettore torna libero (si può riprovare).
  Future<void> toggle(String id, String url) async {
    final p = _ensurePlayer();
    if (state.playingId == id) {
      if (p.playing) {
        await p.pause();
      } else {
        _play(p);
      }
      return;
    }
    await p.stop();
    state = VoiceState(playingId: id);
    try {
      await p.setUrl(url);
    } catch (_) {
      _reset();
      rethrow;
    }
    _play(p);
  }

  Future<void> stop() async {
    await _player?.stop();
    _reset();
  }
}

final voicePlayerProvider = NotifierProvider<VoicePlayer, VoiceState>(
  VoicePlayer.new,
);

/// "0:12" per una durata in secondi.
String formatSeconds(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
