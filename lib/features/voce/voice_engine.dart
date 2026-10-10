import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import 'voice_models.dart';

/// Il motore audio della stanza: Agora sul telefono, finto nella demo e nei test.
abstract class VoiceEngine {
  /// I numeri utente Agora di chi sta parlando in questo momento.
  Stream<Set<int>> get speaking;

  /// Entra nella stanza con il proprio numero utente; [refreshToken] fornisce
  /// un biglietto nuovo quando quello in uso sta per scadere (dopo 3 ore).
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  });

  Future<void> setMuted(bool muted);

  Future<void> setSpeakerphone(bool on);

  /// Esce dalla stanza e libera il motore.
  Future<void> dispose();
}

final voiceEngineFactoryProvider = Provider<VoiceEngine Function()>(
  (ref) => AppConfig.isDemo
      ? () => DemoVoiceEngine(speakingUid: agoraUidFor('p2'))
      : AgoraVoiceEngine.new,
);

/// Stanza vera su Agora (solo audio, profilo "comunicazione").
class AgoraVoiceEngine implements VoiceEngine {
  RtcEngine? _engine;
  final _speaking = StreamController<Set<int>>.broadcast();
  var _local = const <int>{};
  var _remote = const <int>{};
  int _uid = 0;

  @override
  Stream<Set<int>> get speaking => _speaking.stream;

  @override
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  }) async {
    _uid = uid;
    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(
      RtcEngineContext(
        appId: ticket.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        audioScenario: AudioScenarioType.audioScenarioDefault,
      ),
    );
    final joined = Completer<void>();
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, _) {
          if (!joined.isCompleted) joined.complete();
        },
        onError: (err, msg) {
          if (!joined.isCompleted) {
            joined.completeError(
              VoiceException('La stanza non risponde (${err.name}). Riprova.'),
            );
          }
        },
        onConnectionStateChanged: (_, state, reason) {
          if (state == ConnectionStateType.connectionStateFailed &&
              !joined.isCompleted) {
            joined.completeError(
              VoiceException('Connessione fallita (${reason.name}). Riprova.'),
            );
          }
        },
        onAudioVolumeIndication: (_, speakers, _, _) => _onVolumes(speakers),
        onTokenPrivilegeWillExpire: (_, _) => _renew(refreshToken),
      ),
    );
    await engine.enableAudio();
    await engine.enableAudioVolumeIndication(
      interval: 300,
      smooth: 3,
      reportVad: true,
    );
    await engine.setDefaultAudioRouteToSpeakerphone(true);
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
    await joined.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw const VoiceException(
        'La stanza non risponde: controlla la connessione e riprova.',
      ),
    );
  }

  // Il biglietto sta per scadere: se ne chiede uno nuovo e si rinnova senza uscire.
  Future<void> _renew(Future<String> Function()? refreshToken) async {
    if (refreshToken == null) return;
    try {
      final token = await refreshToken();
      await _engine?.renewToken(token);
    } catch (_) {}
  }

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
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await _speaking.close();
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    await engine.release();
  }
}

/// Motore finto: nessun audio, ma [speakingUid] risulta sempre "sta parlando".
class DemoVoiceEngine implements VoiceEngine {
  DemoVoiceEngine({this.speakingUid});
  final int? speakingUid;
  final _speaking = StreamController<Set<int>>.broadcast();

  @override
  Stream<Set<int>> get speaking => _speaking.stream;

  @override
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  }) async {
    _speaking.add({?speakingUid});
  }

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> setSpeakerphone(bool on) async {}

  @override
  Future<void> dispose() => _speaking.close();
}
