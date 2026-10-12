import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/audio_focus.dart';

/// Stato della riproduzione dei vocali: un solo messaggio alla volta.
class VoiceState {
  const VoiceState({
    this.playingId,
    this.loading = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
  });

  /// Messaggio nel lettore (in riproduzione, in pausa o ancora in arrivo).
  final String? playingId;

  /// [playingId] si sta ancora caricando (il link e l'inizio dell'audio).
  final bool loading;
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
    bool? loading,
    bool? playing,
    Duration? position,
    Duration? duration,
  }) => VoiceState(
    playingId: playingId ?? this.playingId,
    loading: loading ?? this.loading,
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

  /// Numero dell'ultimo caricamento: uno superato (intanto si è toccato un altro
  /// vocale, o il lettore si è fermato) finisce in silenzio, senza errori e senza
  /// toccare lo stato del vocale arrivato dopo.
  var _loads = 0;

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
          // Riproduzione interrotta da un errore: si torna da capo (non mentre
          // arriva un altro vocale: l'errore sarebbe del caricamento superato).
          onError: (Object _) {
            if (!state.loading) _reset();
          },
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
    final load = _loads;
    _focus.claim(AudioUse.vocale);
    unawaited(
      p.play().catchError((Object _) {
        if (load == _loads) _reset();
      }),
    );
  }

  /// Ascolta il vocale [id]; se è già nel lettore, pausa o riprendi subito (senza
  /// rete: il link non serve), e mentre arriva un altro tocco lo annulla. [url] dà
  /// il link per caricarlo e si chiede solo allora; se non si carica lancia
  /// l'errore e il lettore torna libero (si può riprovare).
  Future<void> toggle(String id, Future<String> Function() url) async {
    final p = _ensurePlayer();
    if (state.playingId == id) {
      if (state.loading) {
        // Rete lenta: il caricamento si ferma qui, senza errori.
        _loads++;
        _reset();
        await p.stop();
        return;
      }
      if (p.playing) {
        await p.pause();
      } else {
        _play(p);
      }
      return;
    }
    final load = ++_loads;
    bool superseded() => load != _loads || !ref.mounted;
    final link = Future.sync(url)..ignore();
    state = VoiceState(playingId: id, loading: true);
    try {
      await p.stop();
      final address = await link;
      if (superseded()) return;
      await p.setUrl(address);
    } catch (_) {
      // Interrotto perché si è toccato un altro vocale: nessun errore da mostrare.
      if (superseded()) return;
      _reset();
      rethrow;
    }
    if (superseded()) return;
    state = state.copyWith(loading: false);
    _play(p);
  }

  Future<void> stop() async {
    _loads++;
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
