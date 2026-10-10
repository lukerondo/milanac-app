import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import 'voice_models.dart';

abstract class VoiceRepository {
  /// Le stanze aperte adesso (nei canali che si vedono).
  Stream<List<VoiceRoom>> watchOpenRooms();

  /// Chi è dentro la stanza, in tempo reale.
  Stream<List<VoiceSession>> watchSessions(String roomId);

  /// Apre la stanza del canale (o entra in quella aperta); restituisce l'id.
  Future<String> open(String channelId);

  /// Registra il proprio ingresso con il numero utente Agora; restituisce la sessione.
  Future<String> join(String roomId, int agoraUid);

  /// Segno di vita (ogni minuto) con lo stato del microfono.
  Future<void> heartbeat(String sessionId, {required bool muted});

  Future<void> leave(String sessionId);

  /// Biglietto Agora per la stanza.
  Future<VoiceTicket> ticket(String roomId);

  /// Minuti-partecipante usati dal club questo mese.
  Future<int> minutesThisMonth();
}

final voiceRepositoryProvider = Provider<VoiceRepository>((ref) {
  if (AppConfig.isDemo) return DemoVoiceRepository();
  return _SupabaseVoiceRepository(ref);
});

final openVoiceRoomsProvider = StreamProvider<List<VoiceRoom>>(
  (ref) => ref.watch(voiceRepositoryProvider).watchOpenRooms(),
);

/// La stanza aperta di un canale (null se nessuna).
final channelVoiceRoomProvider = Provider.family<VoiceRoom?, String>(
  (ref, channelId) => (ref.watch(openVoiceRoomsProvider).value ?? const [])
      .where((r) => r.channelId == channelId)
      .firstOrNull,
);

final voiceSessionsProvider = StreamProvider.autoDispose
    .family<List<VoiceSession>, String>(
      (ref, roomId) => ref.watch(voiceRepositoryProvider).watchSessions(roomId),
    );

/// Chi è dentro la stanza adesso, nell'ordine di ingresso.
final voiceParticipantsProvider = Provider.autoDispose
    .family<List<VoiceSession>, String>(
      (ref, roomId) =>
          (ref.watch(voiceSessionsProvider(roomId)).value ?? const [])
              .where((s) => s.isActive)
              .toList()
            ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt)),
    );

final voiceMinutesProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(voiceRepositoryProvider).minutesThisMonth(),
);

/// Quanti minuti-partecipante dà il piano gratuito di Agora ogni mese.
const voiceMinutesPerMonth = 10000;

class _SupabaseVoiceRepository implements VoiceRepository {
  _SupabaseVoiceRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Stream<List<VoiceRoom>> watchOpenRooms() => _client
      .from('voice_rooms')
      .stream(primaryKey: ['id'])
      .order('opened_at', ascending: false)
      .limit(30)
      .map(
        (rows) => rows.map(VoiceRoom.fromMap).where((r) => r.isOpen).toList(),
      );

  @override
  Stream<List<VoiceSession>> watchSessions(String roomId) => _client
      .from('voice_sessions')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .map((rows) => rows.map(VoiceSession.fromMap).toList());

  @override
  Future<String> open(String channelId) async =>
      await _client.rpc('open_voice_room', params: {'p_channel': channelId})
          as String;

  @override
  Future<String> join(String roomId, int agoraUid) async => await _client.rpc(
    'join_voice_room',
    params: {'p_room': roomId, 'p_agora_uid': agoraUid},
  ) as String;

  @override
  Future<void> heartbeat(String sessionId, {required bool muted}) async {
    await _client.rpc(
      'voice_heartbeat',
      params: {'p_session': sessionId, 'p_muted': muted},
    );
  }

  @override
  Future<void> leave(String sessionId) async {
    await _client.rpc('leave_voice_room', params: {'p_session': sessionId});
  }

  @override
  Future<VoiceTicket> ticket(String roomId) async {
    final FunctionResponse res;
    try {
      res = await _client.functions.invoke(
        'voice-token',
        body: {'room': roomId},
      );
    } on FunctionException catch (e) {
      if (e.status == 503) {
        throw const VoiceException(
          'La stanza vocale non è ancora attiva: manca la configurazione '
          'Agora (vedi la guida di installazione).',
        );
      }
      if (e.status == 401 || e.status == 403) {
        throw const VoiceException('Non hai accesso a questa stanza.');
      }
      throw VoiceException('Biglietto non ricevuto (${e.status}). Riprova.');
    }
    final data = res.data;
    if (data is! Map) throw const VoiceException('Risposta inattesa. Riprova.');
    return VoiceTicket(
      appId: data['appId'] as String,
      token: data['token'] as String,
      channel: data['channel'] as String,
    );
  }

  @override
  Future<int> minutesThisMonth() async =>
      ((await _client.rpc('voice_minutes')) as num?)?.toInt() ?? 0;
}

/// Stanze in memoria per la modalità demo e i test: in Milan AC c'è già una
/// stanza aperta con Marco e Luca dentro.
class DemoVoiceRepository implements VoiceRepository {
  DemoVoiceRepository() {
    final now = DateTime.now();
    _rooms.add(
      VoiceRoom(
        id: 'vr-milanac',
        channelId: 'c-milanac',
        openedBy: 'p2',
        openedAt: now.subtract(const Duration(minutes: 12)),
      ),
    );
    _sessions.addAll([
      VoiceSession(
        id: 'vs-1',
        roomId: 'vr-milanac',
        userId: 'p2',
        agoraUid: agoraUidFor('p2'),
        joinedAt: now.subtract(const Duration(minutes: 12)),
      ),
      VoiceSession(
        id: 'vs-2',
        roomId: 'vr-milanac',
        userId: 'p3',
        agoraUid: agoraUidFor('p3'),
        joinedAt: now.subtract(const Duration(minutes: 8)),
        muted: true,
      ),
    ]);
  }

  static const _me = 'demo';
  final _rooms = <VoiceRoom>[];
  final _sessions = <VoiceSession>[];
  final _changes = StreamController<void>.broadcast();
  int _next = 10; // le stanze e sessioni di esempio usano i numeri bassi

  void _emit() => _changes.add(null);

  List<VoiceRoom> get _open => _rooms.where((r) => r.isOpen).toList();

  @override
  Stream<List<VoiceRoom>> watchOpenRooms() async* {
    yield _open;
    yield* _changes.stream.map((_) => _open);
  }

  @override
  Stream<List<VoiceSession>> watchSessions(String roomId) async* {
    List<VoiceSession> of() =>
        _sessions.where((s) => s.roomId == roomId).toList();
    yield of();
    yield* _changes.stream.map((_) => of());
  }

  @override
  Future<String> open(String channelId) async {
    final room = _open.where((r) => r.channelId == channelId).firstOrNull;
    if (room != null) return room.id;
    final id = 'vr-${_next++}';
    _rooms.add(
      VoiceRoom(
        id: id,
        channelId: channelId,
        openedBy: _me,
        openedAt: DateTime.now(),
      ),
    );
    _emit();
    return id;
  }

  @override
  Future<String> join(String roomId, int agoraUid) async {
    if (_open.every((r) => r.id != roomId)) {
      throw const VoiceException('Stanza chiusa o non disponibile');
    }
    final i = _sessions.indexWhere(
      (s) => s.roomId == roomId && s.userId == _me && s.isActive,
    );
    if (i >= 0) {
      _sessions[i] = _sessions[i].copyWith(agoraUid: agoraUid);
      _emit();
      return _sessions[i].id;
    }
    final id = 'vs-${_next++}';
    _sessions.add(
      VoiceSession(
        id: id,
        roomId: roomId,
        userId: _me,
        agoraUid: agoraUid,
        joinedAt: DateTime.now(),
      ),
    );
    _emit();
    return id;
  }

  @override
  Future<void> heartbeat(String sessionId, {required bool muted}) async {
    final i = _sessions.indexWhere((s) => s.id == sessionId && s.isActive);
    if (i < 0) return;
    _sessions[i] = _sessions[i].copyWith(muted: muted);
    _emit();
  }

  @override
  Future<void> leave(String sessionId) async {
    final i = _sessions.indexWhere((s) => s.id == sessionId && s.isActive);
    if (i < 0) return;
    final s = _sessions[i].copyWith(leftAt: DateTime.now());
    _sessions[i] = s;
    if (_sessions.every((x) => x.roomId != s.roomId || !x.isActive)) {
      final r = _rooms.indexWhere((r) => r.id == s.roomId);
      if (r >= 0) {
        final room = _rooms[r];
        _rooms[r] = VoiceRoom(
          id: room.id,
          channelId: room.channelId,
          openedBy: room.openedBy,
          openedAt: room.openedAt,
          closedAt: DateTime.now(),
        );
      }
    }
    _emit();
  }

  @override
  Future<VoiceTicket> ticket(String roomId) async =>
      VoiceTicket(appId: 'demo', token: '', channel: roomId);

  @override
  Future<int> minutesThisMonth() async => 1260;
}
