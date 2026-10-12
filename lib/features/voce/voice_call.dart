import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/audio_focus.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/push/push_service.dart' show messengerKey;
import '../chat/chat_repository.dart';
import 'voice_engine.dart';
import 'voice_foreground.dart';
import 'voice_models.dart';
import 'voice_repository.dart';

enum VoicePhase { idle, connecting, inRoom, error }

/// Lo stato della propria presenza nella stanza vocale (una sola alla volta,
/// resta attiva anche cambiando pagina).
class VoiceCallState {
  const VoiceCallState({
    this.phase = VoicePhase.idle,
    this.channel,
    this.roomId,
    this.sessionId,
    this.muted = false,
    this.speakerphone = true,
    this.speaking = const {},
    this.error,
    this.since,
  });

  final VoicePhase phase;
  final Channel? channel;
  final String? roomId;
  final String? sessionId;

  /// Il muto scelto dall'utente (mentre registra un vocale il motore è in muto
  /// comunque, ma qui resta la sua scelta).
  final bool muted;
  final bool speakerphone;

  /// Numeri utente Agora di chi sta parlando adesso.
  final Set<int> speaking;
  final String? error;
  final DateTime? since;

  bool get isActive =>
      phase == VoicePhase.connecting || phase == VoicePhase.inRoom;

  bool isIn(String channelId) => isActive && channel?.id == channelId;

  bool concerns(String channelId) =>
      phase != VoicePhase.idle && channel?.id == channelId;

  VoiceCallState copyWith({
    VoicePhase? phase,
    String? roomId,
    String? sessionId,
    bool? muted,
    bool? speakerphone,
    Set<int>? speaking,
    DateTime? since,
  }) => VoiceCallState(
    phase: phase ?? this.phase,
    channel: channel,
    roomId: roomId ?? this.roomId,
    sessionId: sessionId ?? this.sessionId,
    muted: muted ?? this.muted,
    speakerphone: speakerphone ?? this.speakerphone,
    speaking: speaking ?? this.speaking,
    error: error,
    since: since ?? this.since,
  );
}

class VoiceCall extends Notifier<VoiceCallState> {
  VoiceEngine? _engine;
  Timer? _heartbeat;
  StreamSubscription<Set<int>>? _speakSub;
  StreamSubscription<VoiceException>? _failSub;
  _OnResume? _onResume;
  late VoiceForeground _foreground;
  var _foregroundOn = false;

  /// Numero dell'ingresso in corso: [leave] e ogni nuovo [enter] lo cambiano. Un
  /// ingresso ancora in connessione, al passo successivo, vede di essere superato
  /// e chiude da sé quello che ha aperto (sessione e motore).
  var _attempt = 0;

  /// Finisce quando l'ultimo ingresso (o uscita) ha chiuso i conti con il server:
  /// chi viene dopo lo aspetta, così uscite e ingressi arrivano in ordine.
  Future<void> _settled = Future.value();

  /// Segni di vita periodici falliti di fila (rete assente).
  var _missedBeats = 0;

  /// Si sta registrando un vocale o un replay: il motore è in muto.
  var _recording = false;

  @override
  VoiceCallState build() {
    _foreground = ref.read(voiceForegroundProvider);
    _recording = _isRecording(ref.read(audioFocusProvider));
    ref.listen(audioFocusProvider, (_, uses) {
      final recording = _isRecording(uses);
      if (recording == _recording) return;
      _recording = recording;
      _applyMute();
    });
    // Cambio di account (anche senza logout: account eliminato, sessione scaduta):
    // fuori dalla stanza, dopo il giro in corso (può capitare mentre si disegna).
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != next) scheduleMicrotask(_leaveIfActive);
    });
    ref.onDispose(() {
      _attempt++;
      _teardown();
    });
    return const VoiceCallState();
  }

  /// Entra nella stanza del canale (aprendola se non c'è); se si era in un'altra,
  /// prima ne esce. Finisce quando si è dentro (o l'ingresso non è riuscito).
  Future<void> enter(Channel channel) {
    if (state.isActive && state.channel?.id == channel.id) return _settled;
    final attempt = ++_attempt;
    final previous = _close();
    state = VoiceCallState(phase: VoicePhase.connecting, channel: channel);
    ref.read(audioFocusProvider.notifier).claim(AudioUse.chiamata);
    return _settled = _connect(channel, attempt, previous);
  }

  Future<void> _connect(
    Channel channel,
    int attempt,
    Future<void> previous,
  ) async {
    final repo = ref.read(voiceRepositoryProvider);
    final newEngine = ref.read(voiceEngineFactoryProvider);
    final userId = ref.read(currentUserIdProvider);
    final clock = ref.read(clockProvider);
    bool stale() => attempt != _attempt;
    // Quello che l'ingresso ha aperto e non ha ancora passato alla chiamata: se va
    // male, o se intanto si esce o si cambia stanza, si chiude qui in fondo.
    String? sessionId;
    VoiceEngine? engine;
    try {
      // Prima l'uscita dalla stanza di prima: il server la riceve prima dell'ingresso.
      await previous;
      if (stale()) return;
      if (kIsWeb && !AppConfig.isDemo) {
        throw const VoiceException(
          'La stanza vocale funziona solo dall\'app sul telefono.',
        );
      }
      if (userId == null) {
        throw const VoiceException('Accedi per entrare nella stanza.');
      }
      if (!await _microphoneAllowed()) {
        throw const VoiceException(
          'Serve il permesso del microfono: attivalo nelle impostazioni del '
          'telefono e riprova.',
        );
      }
      if (stale()) return;
      final roomId = await repo.open(channel.id);
      // Aprendo si è già dentro: la sessione serve anche per chiuderla se intanto
      // si è usciti.
      final uid = agoraUidFor(userId);
      sessionId = await repo.join(roomId, uid);
      if (stale()) return;
      final ticket = await repo.ticket(roomId);
      if (stale()) return;
      final joining = engine = newEngine();
      _engine = joining;
      _speakSub = joining.speaking.listen((s) {
        if (attempt == _attempt && state.isActive) {
          state = state.copyWith(speaking: s);
        }
      });
      _failSub = joining.failures.listen((e) => _drop(attempt, e.message));
      await joining.join(
        ticket,
        uid,
        refreshToken: () async => (await repo.ticket(roomId)).token,
      );
      if (stale()) return;
      // Dentro: da qui sessione e motore sono della chiamata (li chiude [leave]).
      state = state.copyWith(
        phase: VoicePhase.inRoom,
        roomId: roomId,
        sessionId: sessionId,
        since: clock(),
      );
      sessionId = null;
      engine = null;
      // Muto e vivavoce toccati durante la connessione arrivano ora al motore.
      unawaited(_applyMute());
      unawaited(_applySpeaker());
      if (state.muted) unawaited(_beat(attempt));
      _missedBeats = 0;
      _heartbeat = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _beat(attempt, periodic: true),
      );
      _onResume = _OnResume(() => _resumed(attempt));
      _startForeground(attempt);
    } catch (e) {
      if (!stale()) {
        final teardown = _teardown();
        state = VoiceCallState(
          phase: VoicePhase.error,
          channel: channel,
          error: _messageOf(e),
        );
        ref.read(audioFocusProvider.notifier).release(AudioUse.chiamata);
        await teardown;
      }
    } finally {
      if (engine != null) {
        try {
          await engine.dispose();
        } catch (_) {}
      }
      if (sessionId != null) {
        try {
          await repo.leave(sessionId);
        } catch (_) {}
      }
    }
  }

  /// Esce dalla stanza (se si era gli ultimi, si chiude), anche durante la
  /// connessione. Finisce quando anche il server ha registrato l'uscita.
  Future<void> leave() {
    _attempt++;
    final closing = _settled = _close();
    state = const VoiceCallState();
    ref.read(audioFocusProvider.notifier).release(AudioUse.chiamata);
    return closing;
  }

  Future<void> toggleMute() async {
    state = state.copyWith(muted: !state.muted);
    // In connessione il motore non è ancora pronto: il muto arriva appena dentro.
    await _applyMute();
    // Gli altri vedono subito il microfono barrato.
    await _beat(_attempt);
  }

  Future<void> toggleSpeakerphone() async {
    state = state.copyWith(speakerphone: !state.speakerphone);
    await _applySpeaker();
  }

  void dismissError() {
    if (state.phase == VoicePhase.error) state = const VoiceCallState();
  }

  /// Chiude la chiamata attuale: subito motore, segno di vita e avviso; poi,
  /// dopo l'ingresso o l'uscita ancora in corso, l'uscita sul server. Un ingresso
  /// ancora in connessione chiude da sé la sua sessione.
  Future<void> _close() {
    final sessionId = state.sessionId;
    final previous = _settled;
    final repo = ref.read(voiceRepositoryProvider);
    final teardown = _teardown();
    return () async {
      await teardown;
      await previous;
      if (sessionId != null) {
        try {
          await repo.leave(sessionId);
        } catch (_) {}
      }
    }();
  }

  /// La chiamata è caduta (sessione chiusa dal server, rete assente, connessione
  /// persa): si esce del tutto e lo si dice, anche con la stanza ridotta a striscia.
  void _drop(int attempt, String message) {
    if (attempt != _attempt || state.phase != VoicePhase.inRoom) return;
    _attempt++;
    final channel = state.channel;
    _settled = _close();
    state = VoiceCallState(
      phase: VoicePhase.error,
      channel: channel,
      error: message,
    );
    ref.read(audioFocusProvider.notifier).release(AudioUse.chiamata);
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Segno di vita: se il server ha già chiuso la sessione, o la rete manca da
  /// 3 minuti (il server l'avrà chiusa), la chiamata finisce con il motivo.
  Future<void> _beat(int attempt, {bool periodic = false}) async {
    if (attempt != _attempt) return;
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final repo = ref.read(voiceRepositoryProvider);
    final bool alive;
    try {
      alive = await repo.heartbeat(sessionId, muted: state.muted);
    } catch (_) {
      if (periodic && attempt == _attempt && ++_missedBeats >= 3) {
        _drop(
          attempt,
          'Connessione persa: sei uscito dalla stanza. Rientra quando torna '
          'la rete.',
        );
      }
      return;
    }
    if (attempt != _attempt) return;
    _missedBeats = 0;
    if (!alive) _drop(attempt, voiceLeftMessage);
  }

  // Ritorno nell'app: subito un segno di vita (se il server ci ha fatto uscire
  // mentre eravamo via, lo si dice adesso) e l'avviso fisso, se non era partito.
  void _resumed(int attempt) {
    if (attempt != _attempt) return;
    if (!_foregroundOn) _startForeground(attempt);
    unawaited(_beat(attempt));
  }

  void _startForeground(int attempt) {
    final channel = state.channel;
    if (channel == null) return;
    _foregroundOn = true;
    unawaited(
      _foreground.start(channel.name).then((ok) {
        if (!ok && attempt == _attempt) _foregroundOn = false;
      }),
    );
  }

  /// Il motore riceve il muto scelto dall'utente, più quello mentre si registra
  /// un vocale o un replay (che finita la registrazione torna come prima).
  Future<void> _applyMute() async {
    final engine = _engine;
    if (engine == null || state.phase != VoicePhase.inRoom) return;
    try {
      await engine.setMuted(state.muted || _recording);
    } catch (_) {}
  }

  Future<void> _applySpeaker() async {
    final engine = _engine;
    if (engine == null || state.phase != VoicePhase.inRoom) return;
    try {
      await engine.setSpeakerphone(state.speakerphone);
    } catch (_) {}
  }

  void _leaveIfActive() {
    if (ref.mounted && state.phase != VoicePhase.idle) leave();
  }

  Future<bool> _microphoneAllowed() async {
    if (AppConfig.isDemo) return true;
    // Serve solo per chiedere il permesso: poi si libera.
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission();
    } catch (_) {
      return false;
    } finally {
      unawaited(recorder.dispose().catchError((_) {}));
    }
  }

  /// Ferma subito motore, segno di vita e avviso della chiamata attuale.
  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _onResume?.dispose();
    _onResume = null;
    // Senza await: il future di cancel() vive nella zona radice e nei test con
    // il tempo finto non si completerebbe mai.
    _speakSub?.cancel();
    _speakSub = null;
    _failSub?.cancel();
    _failSub = null;
    if (_foregroundOn) {
      _foregroundOn = false;
      unawaited(_foreground.stop());
    }
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
  }

  static bool _isRecording(Set<AudioUse> uses) =>
      uses.contains(AudioUse.registrazioneVocale) ||
      uses.contains(AudioUse.registrazioneReplay);

  static String _messageOf(Object e) => e is VoiceException
      ? e.message
      : friendlyError(e, action: 'Non riesco a entrare nella stanza');
}

final voiceCallProvider = NotifierProvider<VoiceCall, VoiceCallState>(
  VoiceCall.new,
);

/// Chiama [onResume] a ogni ritorno dell'app in primo piano.
class _OnResume with WidgetsBindingObserver {
  _OnResume(this.onResume) {
    WidgetsBinding.instance.addObserver(this);
  }

  final void Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
