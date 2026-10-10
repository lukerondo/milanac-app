import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

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

/// Lettore condiviso dei messaggi vocali (just_audio), creato al primo ascolto.
class VoicePlayer extends Notifier<VoiceState> {
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  VoiceState build() {
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _player?.dispose();
    });
    return const VoiceState();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _subs
      ..add(
        p.positionStream.listen((pos) => state = state.copyWith(position: pos)),
      )
      ..add(
        p.durationStream.listen((d) => state = state.copyWith(duration: d)),
      )
      ..add(
        p.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            p.pause();
            p.seek(Duration.zero);
            state = state.copyWith(playing: false, position: Duration.zero);
          } else {
            state = state.copyWith(playing: s.playing);
          }
        }),
      );
    return _player = p;
  }

  /// Ascolta il vocale [id] (indirizzo [url]); se è già caricato, pausa/riprendi.
  Future<void> toggle(String id, String url) async {
    final p = _ensurePlayer();
    if (state.playingId == id) {
      if (p.playing) {
        await p.pause();
      } else {
        unawaited(p.play());
      }
      return;
    }
    await p.stop();
    state = VoiceState(playingId: id);
    await p.setUrl(url);
    unawaited(p.play());
  }

  Future<void> stop() async {
    await _player?.stop();
    state = const VoiceState();
  }
}

final voicePlayerProvider = NotifierProvider<VoicePlayer, VoiceState>(
  VoicePlayer.new,
);

/// "0:12" per una durata in secondi.
String formatSeconds(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
