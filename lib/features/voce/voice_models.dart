/// Stanza vocale aperta in un canale della chat (una sola per canale).
class VoiceRoom {
  const VoiceRoom({
    required this.id,
    required this.channelId,
    required this.openedAt,
    this.openedBy,
    this.closedAt,
  });

  final String id;
  final String channelId;
  final DateTime openedAt;
  final String? openedBy;
  final DateTime? closedAt;

  bool get isOpen => closedAt == null;

  factory VoiceRoom.fromMap(Map<String, dynamic> m) => VoiceRoom(
    id: m['id'] as String,
    channelId: m['channel_id'] as String,
    openedBy: m['opened_by'] as String?,
    openedAt: DateTime.parse(m['opened_at'] as String).toLocal(),
    closedAt: m['closed_at'] == null
        ? null
        : DateTime.parse(m['closed_at'] as String).toLocal(),
  );
}

/// Un ingresso nella stanza: chi, da quando, con il microfono acceso o spento.
class VoiceSession {
  const VoiceSession({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.joinedAt,
    this.agoraUid,
    this.leftAt,
    this.muted = false,
  });

  final String id;
  final String roomId;
  final String userId;
  final DateTime joinedAt;

  /// Numero utente in Agora (vedi [agoraUidFor]): serve a capire chi sta parlando.
  final int? agoraUid;
  final DateTime? leftAt;
  final bool muted;

  bool get isActive => leftAt == null;

  VoiceSession copyWith({int? agoraUid, DateTime? leftAt, bool? muted}) =>
      VoiceSession(
        id: id,
        roomId: roomId,
        userId: userId,
        joinedAt: joinedAt,
        agoraUid: agoraUid ?? this.agoraUid,
        leftAt: leftAt ?? this.leftAt,
        muted: muted ?? this.muted,
      );

  factory VoiceSession.fromMap(Map<String, dynamic> m) => VoiceSession(
    id: m['id'] as String,
    roomId: m['room_id'] as String,
    userId: m['user_id'] as String,
    agoraUid: (m['agora_uid'] as num?)?.toInt(),
    joinedAt: DateTime.parse(m['joined_at'] as String).toLocal(),
    leftAt: m['left_at'] == null
        ? null
        : DateTime.parse(m['left_at'] as String).toLocal(),
    muted: m['muted'] as bool? ?? false,
  );
}

/// Biglietto d'ingresso in Agora, generato dalla funzione Edge `voice-token`.
class VoiceTicket {
  const VoiceTicket({
    required this.appId,
    required this.token,
    required this.channel,
  });
  final String appId;
  final String token;
  final String channel;
}

/// Qualcosa è andato storto nella stanza: [message] è già pronto per l'utente.
class VoiceException implements Exception {
  const VoiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Numero utente Agora ricavato dall'id del profilo: sempre lo stesso per la
/// stessa persona, così la stanza sa subito chi sta parlando (i biglietti sono
/// validi per qualsiasi numero).
int agoraUidFor(String userId) {
  var h = 0;
  for (final c in userId.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h == 0 ? 1 : h;
}
