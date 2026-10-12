import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import 'voice_models.dart';

/// Il motore audio della stanza: Agora sul telefono, finto nella demo e nei test.
/// Serve per un solo ingresso: dopo [dispose] se ne crea uno nuovo.
abstract class VoiceEngine {
  /// I numeri utente Agora di chi sta parlando in questo momento.
  Stream<Set<int>> get speaking;

  /// La chiamata è caduta dopo l'ingresso (connessione persa, biglietto non
  /// rinnovato): il messaggio è già pronto per l'utente.
  Stream<VoiceException> get failures;

  /// Entra nella stanza con il proprio numero utente; [refreshToken] fornisce
  /// un biglietto nuovo quando quello in uso sta per scadere (dopo un'ora).
  /// Se nel frattempo arriva [dispose], si interrompe con un errore.
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  });

  /// Solo dopo [join].
  Future<void> setMuted(bool muted);

  /// Solo dopo [join].
  Future<void> setSpeakerphone(bool on);

  /// Esce dalla stanza e libera il motore (anche a join in corso; chiamarlo più
  /// volte non fa danni).
  Future<void> dispose();
}

final voiceEngineFactoryProvider = Provider<VoiceEngine Function()>(
  (ref) => AppConfig.isDemo
      ? () => DemoVoiceEngine(speakingUid: agoraUidFor('p2'))
      : AgoraVoiceEngine.new,
);

/// Rinnovo del biglietto della stanza: chiede quello nuovo con [refresh] e lo passa
/// ad Agora con [apply]. Un errore di rete (o del server) non chiude la chiamata: si
/// riprova dopo 2, 4, 8 secondi... finché il biglietto vale ([until]). Una risposta
/// definitiva ([VoiceException]: non sei più nella stanza, stanza chiusa) non si
/// riprova. Restituisce il motivo per cui non è riuscito, null se è riuscito o se
/// intanto si è usciti ([stopped]).
Future<VoiceException?> renewVoiceTicket({
  required Future<String> Function() refresh,
  required Future<void> Function(String token) apply,
  required bool Function() stopped,
  required DateTime until,
  DateTime Function() now = DateTime.now,
  Future<void> Function(Duration) wait = _wait,
}) async {
  var pause = const Duration(seconds: 2);
  while (!stopped()) {
    try {
      await apply(await refresh());
      return null;
    } on VoiceException catch (e) {
      return stopped() ? null : e;
    } catch (_) {
      if (stopped()) return null;
      if (now().add(pause).isAfter(until)) {
        return const VoiceException(
          'Biglietto della stanza non rinnovato: controlla la rete e rientra.',
        );
      }
      await wait(pause);
      if (pause < const Duration(seconds: 8)) pause *= 2;
    }
  }
  return null;
}

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// Stanza vera su Agora (solo audio, profilo "comunicazione").
class AgoraVoiceEngine implements VoiceEngine {
  RtcEngine? _engine;
  final _speaking = StreamController<Set<int>>.broadcast();
  final _failures = StreamController<VoiceException>.broadcast();
  // L'esito può arrivare (anche come errore) prima che qualcuno lo aspetti.
  final _joined = Completer<void>()..future.ignore();
  Future<void>? _setup;
  Future<void>? _disposed;
  Future<String> Function()? _refreshToken;

  /// Rinnovo del biglietto in corso: un altro avviso di Agora non ne avvia un secondo.
  var _renewing = false;
  var _local = const <int>{};
  var _remote = const <int>{};
  int _uid = 0;

  @override
  Stream<Set<int>> get speaking => _speaking.stream;

  @override
  Stream<VoiceException> get failures => _failures.stream;

  @override
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  }) async {
    _uid = uid;
    _refreshToken = refreshToken;
    final setup = Completer<void>();
    _setup = setup.future;
    try {
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(
        RtcEngineContext(
          appId: ticket.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          audioScenario: AudioScenarioType.audioScenarioDefault,
        ),
      );
      _checkOpen();
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, _) {
            if (!_joined.isCompleted) _joined.complete();
          },
          onError: (err, msg) {
            if (!_joined.isCompleted) {
              _joined.completeError(
                VoiceException(
                  'La stanza non risponde (${err.name}). Riprova.',
                ),
              );
            }
          },
          onConnectionStateChanged: (_, state, reason) {
            if (state != ConnectionStateType.connectionStateFailed) return;
            if (_joined.isCompleted) {
              // Agora ha smesso di riprovare (rete assente da 20 minuti,
              // biglietto non valido, uscita forzata): la chiamata è finita.
              _fail(VoiceException(_lostMessage(reason)));
            } else {
              _joined.completeError(
                VoiceException(
                  'Connessione fallita (${reason.name}). Riprova.',
                ),
              );
            }
          },
          onAudioVolumeIndication: (_, speakers, _, _) => _onVolumes(speakers),
          // Agora avvisa 30 secondi prima della scadenza; se il biglietto è già
          // scaduto lo chiede di nuovo: si prova ancora per qualche secondo.
          onTokenPrivilegeWillExpire: (_, _) =>
              _renew(const Duration(seconds: 30)),
          onRequestToken: (_) => _renew(const Duration(seconds: 10)),
        ),
      );
      await engine.enableAudio();
      _checkOpen();
      await engine.enableAudioVolumeIndication(
        interval: 300,
        smooth: 3,
        reportVad: true,
      );
      _checkOpen();
      await engine.setDefaultAudioRouteToSpeakerphone(true);
      _checkOpen();
      await engine.joinChannel(
        token: ticket.token,
        channelId: ticket.channel,
        uid: uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
        ),
      );
    } finally {
      setup.complete();
    }
    await _joined.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw const VoiceException(
        'La stanza non risponde: controlla la connessione e riprova.',
      ),
    );
  }

  // Uscita chiesta durante la join: ci si ferma qui (il motore lo libera dispose).
  void _checkOpen() {
    if (_disposed != null) {
      throw const VoiceException('Sei uscito dalla stanza.');
    }
  }

  // Il biglietto sta per scadere (o è scaduto): se ne chiede uno nuovo e si rinnova
  // senza uscire, riprovando finché vale ancora ([validFor]). Se non arriva (non si
  // è più nella stanza, rete assente fino alla scadenza) la chiamata finisce con il
  // motivo, invece di cadere in silenzio.
  Future<void> _renew(Duration validFor) async {
    final refresh = _refreshToken;
    if (refresh == null || _renewing) return;
    _renewing = true;
    try {
      final problem = await renewVoiceTicket(
        refresh: refresh,
        apply: (token) async {
          await _engine?.renewToken(token);
        },
        stopped: () => _disposed != null,
        until: DateTime.now().add(validFor),
      );
      if (problem != null) _fail(problem);
    } finally {
      _renewing = false;
    }
  }

  void _fail(VoiceException e) {
    if (!_failures.isClosed) _failures.add(e);
  }

  static String _lostMessage(ConnectionChangedReasonType reason) =>
      switch (reason) {
        ConnectionChangedReasonType.connectionChangedTokenExpired ||
        ConnectionChangedReasonType.connectionChangedInvalidToken =>
          'Il biglietto della stanza non è più valido: rientra.',
        ConnectionChangedReasonType.connectionChangedBannedByServer ||
        ConnectionChangedReasonType.connectionChangedRejectedByServer =>
          'La stanza ti ha fatto uscire: rientra.',
        ConnectionChangedReasonType.connectionChangedSameUidLogin =>
          'Sei entrato nella stanza da un altro telefono.',
        _ => 'Connessione con la stanza persa: controlla la rete e rientra.',
      };

  // Agora avvisa due volte: una per il proprio microfono (uid 0) e una per gli altri.
  void _onVolumes(List<AudioVolumeInfo> speakers) {
    final isLocal = speakers.any((s) => s.uid == 0);
    final loud = <int>{
      for (final s in speakers)
        if (s.vad == 1 || (s.volume ?? 0) > 20) s.uid == 0 ? _uid : s.uid!,
    };
    if (isLocal) {
      _local = loud;
    } else {
      _remote = loud;
    }
    if (!_speaking.isClosed) _speaking.add({..._local, ..._remote});
  }

  @override
  Future<void> setMuted(bool muted) async =>
      _engine?.muteLocalAudioStream(muted);

  @override
  Future<void> setSpeakerphone(bool on) async =>
      _engine?.setEnableSpeakerphone(on);

  @override
  Future<void> dispose() => _disposed ??= _release();

  Future<void> _release() async {
    // Una join in attesa della risposta si ferma subito.
    if (!_joined.isCompleted) {
      _joined.completeError(const VoiceException('Sei uscito dalla stanza.'));
    }
    unawaited(_speaking.close());
    unawaited(_failures.close());
    // Prima finiscono le chiamate della join già partite (inizializzazione compresa):
    // liberare il motore a metà potrebbe bloccarle.
    final setup = _setup;
    if (setup != null) await setup;
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
  }
}

/// Motore finto: nessun audio, ma [speakingUid] risulta sempre "sta parlando".
///
/// Nei test: [connecting] tiene la join in sospeso finché non si completa (rete
/// lenta), [fail] fa cadere la chiamata; [joined], [muted], [speakerphone] e
/// [disposed] dicono che cosa ha ricevuto il motore.
class DemoVoiceEngine implements VoiceEngine {
  DemoVoiceEngine({this.speakingUid, this.connecting});
  final int? speakingUid;
  final Future<void>? connecting;
  final _speaking = StreamController<Set<int>>.broadcast();
  final _failures = StreamController<VoiceException>.broadcast();
  final _released = Completer<void>();

  bool joined = false;
  bool muted = false;
  bool speakerphone = false;
  bool get disposed => _released.isCompleted;

  @override
  Stream<Set<int>> get speaking => _speaking.stream;

  @override
  Stream<VoiceException> get failures => _failures.stream;

  @override
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  }) async {
    final wait = connecting;
    if (wait != null) await Future.any([wait, _released.future]);
    if (disposed) throw const VoiceException('Sei uscito dalla stanza.');
    joined = true;
    _speaking.add({?speakingUid});
  }

  /// La connessione cade dopo l'ingresso (come Agora che smette di riprovare).
  void fail(String message) {
    if (!_failures.isClosed) _failures.add(VoiceException(message));
  }

  @override
  Future<void> setMuted(bool muted) async {
    this.muted = muted;
  }

  @override
  Future<void> setSpeakerphone(bool on) async {
    speakerphone = on;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    _released.complete();
    unawaited(_speaking.close());
    unawaited(_failures.close());
  }
}
