import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/config.dart';
import '../chat/chat_repository.dart';
import 'voice_engine.dart';
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

  @override
  VoiceCallState build() {
    ref.onDispose(_teardown);
    return const VoiceCallState();
  }

  /// Entra nella stanza del canale (aprendola se non c'è).
  Future<void> enter(Channel channel) async {
    if (state.isActive) {
      if (state.channel?.id == channel.id) return;
      await leave();
    }
    state = VoiceCallState(phase: VoicePhase.connecting, channel: channel);
    final repo = ref.read(voiceRepositoryProvider);
    String? sessionId;
    try {
      if (kIsWeb && !AppConfig.isDemo) {
        throw const VoiceException(
          'La stanza vocale funziona solo dall\'app sul telefono.',
        );
      }
      final userId = ref.read(profileProvider).value?.id;
      if (userId == null) {
        throw const VoiceException('Accedi per entrare nella stanza.');
      }
      if (!await _microphoneAllowed()) {
        throw const VoiceException(
          'Serve il permesso del microfono: attivalo nelle impostazioni del '
          'telefono e riprova.',
        );
      }
      final roomId = await repo.open(channel.id);
      final uid = agoraUidFor(userId);
      sessionId = await repo.join(roomId, uid);
      final ticket = await repo.ticket(roomId);
      final engine = ref.read(voiceEngineFactoryProvider)();
      _engine = engine;
      _speakSub = engine.speaking.listen((s) {
        if (state.isActive) state = state.copyWith(speaking: s);
      });
      await engine.join(ticket, uid);
      await engine.setSpeakerphone(true);
      final session = sessionId;
      _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
        repo.heartbeat(session, muted: state.muted).catchError((_) {});
      });
      state = state.copyWith(
        phase: VoicePhase.inRoom,
        roomId: roomId,
        sessionId: sessionId,
        since: ref.read(clockProvider)(),
      );
    } catch (e) {
      await _teardown();
      if (sessionId != null) {
        try {
          await repo.leave(sessionId);
        } catch (_) {}
      }
      state = VoiceCallState(
        phase: VoicePhase.error,
        channel: channel,
        error: _messageOf(e),
      );
    }
  }

  /// Esce dalla stanza (se si era gli ultimi, si chiude).
  Future<void> leave() async {
    final sessionId = state.sessionId;
    final repo = ref.read(voiceRepositoryProvider);
    await _teardown();
    state = const VoiceCallState();
    if (sessionId != null) {
      try {
        await repo.leave(sessionId);
      } catch (_) {}
    }
  }

  Future<void> toggleMute() async {
    final muted = !state.muted;
    state = state.copyWith(muted: muted);
    await _engine?.setMuted(muted);
    final sessionId = state.sessionId;
    if (sessionId != null) {
      try {
        await ref
            .read(voiceRepositoryProvider)
            .heartbeat(sessionId, muted: muted);
      } catch (_) {}
    }
  }

  Future<void> toggleSpeakerphone() async {
    final on = !state.speakerphone;
    state = state.copyWith(speakerphone: on);
    await _engine?.setSpeakerphone(on);
  }

  void dismissError() {
    if (state.phase == VoicePhase.error) state = const VoiceCallState();
  }

  Future<bool> _microphoneAllowed() async {
    if (AppConfig.isDemo) return true;
    try {
      return await AudioRecorder().hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    // Senza await: il future di cancel() vive nella zona radice e nei test con
    // il tempo finto non si completerebbe mai.
    _speakSub?.cancel();
    _speakSub = null;
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
  }

  static String _messageOf(Object e) => switch (e) {
    VoiceException(:final message) => message,
    PostgrestException(:final message) => message,
    _ => 'Non riesco a entrare nella stanza. Riprova.',
  };
}

final voiceCallProvider = NotifierProvider<VoiceCall, VoiceCallState>(
  VoiceCall.new,
);
