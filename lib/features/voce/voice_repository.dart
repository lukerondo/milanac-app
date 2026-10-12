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

  /// Segno di vita (ogni minuto) con lo stato del microfono; false se il server
  /// ha già chiuso la sessione (per esempio dopo 3 minuti senza segnale).
  Future<bool> heartbeat(String sessionId, {required bool muted});

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

// Come i dati della chat, le stanze dipendono da chi è entrato (si vedono quelle dei
// suoi canali): con un altro account sullo stesso telefono si ricaricano da zero.

final openVoiceRoomsProvider = StreamProvider<List<VoiceRoom>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const []);
  return ref.watch(voiceRepositoryProvider).watchOpenRooms();
});

/// La stanza aperta di un canale (null se nessuna).
final channelVoiceRoomProvider = Provider.family<VoiceRoom?, String>(
  (ref, channelId) => (ref.watch(openVoiceRoomsProvider).value ?? const [])
      .where((r) => r.channelId == channelId)
      .firstOrNull,
);

final voiceSessionsProvider = StreamProvider.autoDispose
    .family<List<VoiceSession>, String>((ref, roomId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(voiceRepositoryProvider).watchSessions(roomId);
    });

/// Chi è dentro la stanza adesso, nell'ordine di ingresso.
final voiceParticipantsProvider = Provider.autoDispose
    .family<List<VoiceSession>, String>(
      (ref, roomId) =>
          (ref.watch(voiceSessionsProvider(roomId)).value ?? const [])
              .where((s) => s.isActive)
              .toList()
            ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt)),
    );

final voiceMinutesProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(voiceRepositoryProvider).minutesThisMonth();
});

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
  Future<bool> heartbeat(String sessionId, {required bool muted}) async {
    final alive = await _client.rpc(
      'voice_heartbeat',
      params: {'p_session': sessionId, 'p_muted': muted},
    );
    // Prima della migrazione 0023 la funzione non restituiva niente: ancora dentro.
    return alive != false;
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
    } on FunctionsFetchException {
      // Rete assente: niente risposta dal server (lo dice chi chiama).
      rethrow;
    } on FunctionException catch (e) {
      if (e.status == 409) throw const VoiceException(voiceLeftMessage);
      if (e.status == 404) {
        throw const VoiceException(
          'La stanza è stata chiusa: entra di nuovo per riaprirla.',
        );
      }
      if (e.status == 503) {
        throw const VoiceException(
          'La stanza vocale non è ancora attiva: manca la configurazione '
          'Agora (vedi la guida di installazione).',
        );
      }
      if (e.status == 401 || e.status == 403) {
        throw const VoiceException('Non hai accesso a questa stanza.');
      }
      // Altri errori del server (5xx, troppe richieste): passano, si può riprovare
      // (il rinnovo del biglietto durante la chiamata lo fa da solo).
      rethrow;
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

  /// Tutte le sessioni, chiuse comprese (per i test).
  List<VoiceSession> get sessions => List.unmodifiable(_sessions);

  @override
  Future<String> open(String channelId) async {
    var room = _open.where((r) => r.channelId == channelId).firstOrNull?.id;
    if (room == null) {
      room = 'vr-${_next++}';
      _rooms.add(
        VoiceRoom(
          id: room,
          channelId: channelId,
          openedBy: _me,
          openedAt: DateTime.now(),
        ),
      );
    }
    // Come sul server: chi apre la stanza (o la trova aperta) è già dentro.
    _enter(room);
    _emit();
    return room;
  }

  @override
  Future<String> join(String roomId, int agoraUid) async {
    if (_open.every((r) => r.id != roomId)) {
      throw const VoiceException('Stanza chiusa o non disponibile');
    }
    final id = _enter(roomId);
    _emit();
    return id;
  }

  // Una stanza per volta, come sul server: le altre sessioni aperte si chiudono.
  String _enter(String roomId) {
    for (final s in _sessions.toList()) {
      if (s.userId == _me && s.isActive && s.roomId != roomId) _close(s.id);
    }
    final mine = _sessions
        .where((s) => s.roomId == roomId && s.userId == _me && s.isActive)
        .firstOrNull;
    if (mine != null) return mine.id;
    final id = 'vs-${_next++}';
    _sessions.add(
      VoiceSession(
        id: id,
        roomId: roomId,
        userId: _me,
        agoraUid: agoraUidFor(_me),
        joinedAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<bool> heartbeat(String sessionId, {required bool muted}) async {
    final i = _sessions.indexWhere((s) => s.id == sessionId && s.isActive);
    if (i < 0) return false;
    _sessions[i] = _sessions[i].copyWith(muted: muted);
    _emit();
    return true;
  }

  @override
  Future<void> leave(String sessionId) async {
    _close(sessionId);
    _emit();
  }

  // Chiude la sessione; se era l'ultima, anche la stanza.
  void _close(String sessionId) {
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
  }

  @override
  Future<VoiceTicket> ticket(String roomId) async {
    // Come la funzione voice-token: il biglietto solo a chi ha una sessione aperta.
    if (!_sessions.any(
      (s) => s.roomId == roomId && s.userId == _me && s.isActive,
    )) {
      throw const VoiceException(voiceLeftMessage);
    }
    return VoiceTicket(appId: 'demo', token: '', channel: roomId);
  }

  @override
  Future<int> minutesThisMonth() async => 1260;
}
