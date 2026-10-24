import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import '../lavagna/board_model.dart';

const chatBucket = 'chat';

/// Durata massima di un messaggio vocale e di un replay della lavagna.
const maxVoiceSeconds = 120;
const maxReplaySeconds = 300;

/// Messaggi più recenti seguiti in tempo reale; i precedenti arrivano a pagine
/// scorrendo in cima alla conversazione.
const chatRecentLimit = 50;
const chatPageSize = 50;

/// I link firmati di foto e vocali valgono 6 ore: si rinnovano prima che scadano.
const chatImageUrlLifetime = Duration(hours: 5);

/// Ricerca nei messaggi: dalle 2 lettere in su, gli ultimi 50 risultati.
const chatSearchMinLength = 2;
const chatSearchLimit = 50;

/// [text] da cercare letteralmente con like/ilike: `%`, `_` e la barra rovesciata
/// non fanno da caratteri jolly.
String escapeLikePattern(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Canale della chat (tabella `channels`).
class Channel {
  const Channel({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.icon = 'chat',
    this.direttivoOnly = false,
    this.team,
    this.direttivoWrites = false,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String icon;

  /// Canale riservato al Direttivo (Sala Direttivo).
  final bool direttivoOnly;

  /// Canale di una squadra (milanac o futuro): lo vede chi ci gioca.
  final String? team;

  /// Vi scrive solo il Direttivo (Comunicazioni).
  final bool direttivoWrites;

  IconData get iconData => direttivoOnly
      ? Icons.lock_rounded
      : switch (icon) {
          'forum' => Icons.chat_bubble_rounded,
          'team' => Icons.groups_rounded,
          'campaign' => Icons.campaign_rounded,
          'tattiche' => Icons.draw_rounded,
          'direttivo' => Icons.lock_rounded,
          _ => Icons.chat_bubble_rounded,
        };

  /// La descrizione in breve, per una riga: la parte prima dei due punti
  /// ("Solo per il Direttivo: decisioni, mercato…" → "Solo per il Direttivo").
  String get shortDescription => (description ?? '').split(':').first.trim();

  /// Chi legge il canale (sottotitolo della conversazione).
  String get audience {
    if (direttivoOnly) return 'Solo il Direttivo';
    final squad = Team.parse(team);
    if (squad != null) return 'La squadra ${squad.label}';
    return direttivoWrites
        ? 'Tutto il club · scrive il Direttivo'
        : 'Tutto il club';
  }

  factory Channel.fromMap(Map<String, dynamic> m) => Channel(
    id: m['id'] as String,
    slug: m['slug'] as String,
    name: m['name'] as String,
    description: m['description'] as String?,
    icon: (m['icon'] as String?) ?? 'chat',
    direttivoOnly: (m['direttivo_only'] as bool?) ?? false,
    team: m['team'] as String?,
    direttivoWrites: (m['direttivo_writes'] as bool?) ?? false,
  );
}

/// Messaggio (tabella `messages`). I messaggi "system" sono scritti dal database
/// (formazione pubblicata, carte speciali della giornata).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.createdAt,
    this.authorId,
    this.isSystem = false,
    this.body,
    this.imagePath,
    this.audioPath,
    this.durationS,
    this.replayPath,
    this.replyTo,
    this.expiresAt,
    this.expiredAt,
    this.meta = const {},
    this.localImage,
    this.localAudio,
    this.localReplay,
    this.sending = false,
    this.failed = false,
    this.waiting = false,
  });

  final String id;
  final String channelId;
  final String? authorId;
  final bool isSystem;
  final String? body;
  final String? imagePath;

  /// Messaggio vocale: file nel bucket e durata in secondi.
  final String? audioPath;
  final int? durationS;

  /// Replay della lavagna: file JSON con le azioni e i tempi (l'audio è in [audioPath]).
  final String? replayPath;

  /// Messaggio a cui si risponde (stesso canale).
  final String? replyTo;

  /// Foto e vocali scadono dopo 60 giorni: il messaggio resta con "Allegato scaduto".
  final DateTime? expiresAt;
  final DateTime? expiredAt;

  /// Dati in più scritti dal database o dall'app (jsonb libero: si legge senza fidarsi).
  final Map<String, dynamic> meta;
  final DateTime createdAt;

  /// Foto, vocale e replay tenuti in memoria: nella demo e, sul telefono di chi
  /// scrive, per i messaggi appena inviati.
  final Uint8List? localImage;
  final Uint8List? localAudio;
  final Uint8List? localReplay;

  /// Solo sul telefono di chi scrive: il messaggio compare subito, mentre parte...
  final bool sending;

  /// ...oppure non è partito (si riprova toccandolo)...
  final bool failed;

  /// ...oppure aspetta la rete: riparte da solo appena torna (anche dopo aver
  /// chiuso l'app), o subito toccandolo.
  final bool waiting;

  /// Non ancora salvato dal server.
  bool get isLocal => sending || failed || waiting;

  bool get hasImage => imagePath != null || localImage != null;
  bool get hasAudio => audioPath != null || localAudio != null;
  bool get hasReplay => replayPath != null || localReplay != null;

  /// Replay della lavagna (anche scaduto: resta il titolo).
  bool get isReplay => meta['type'] == 'replay';
  bool get isExpired => expiredAt != null;
  bool get hasText => body != null && body!.trim().isNotEmpty;

  /// Avviso ufficiale del Direttivo (evidenziato in chat, titolo dedicato nella notifica).
  bool get isAnnouncement => meta['type'] == 'announcement';

  /// Tipo del messaggio automatico (formation, special_cards...); vuoto se manca.
  String get systemType {
    final type = meta['type'];
    return type is String ? type : '';
  }

  /// Titolo del replay (null se manca o non è un testo).
  String? get replayTitle {
    final title = meta['title'];
    return title is String && title.trim().isNotEmpty ? title.trim() : null;
  }

  /// Testo breve per anteprime e citazioni.
  String get summary => isReplay
      ? '🎬 Schema con audio${replayTitle == null ? '' : ': $replayTitle'}'
      : hasText
      ? body!.trim()
      : hasImage
      ? '📷 Foto'
      : hasAudio
      ? '🎤 Messaggio vocale'
      : isExpired
      ? 'Allegato scaduto'
      : '';

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    DateTime? when(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    final createdAt = when(m['created_at']);
    if (createdAt == null) {
      throw FormatException('Messaggio senza data: ${m['id']}');
    }
    final meta = m['meta'];
    return ChatMessage(
      id: m['id'] as String,
      channelId: m['channel_id'] as String,
      authorId: m['author_id'] as String?,
      isSystem: m['kind'] == 'system',
      body: m['body'] as String?,
      imagePath: m['image_path'] as String?,
      audioPath: m['audio_path'] as String?,
      durationS: (m['duration_s'] as num?)?.toInt(),
      replayPath: m['replay_path'] as String?,
      replyTo: m['reply_to'] as String?,
      expiresAt: when(m['expires_at']),
      expiredAt: when(m['expired_at']),
      // Un meta che non è un oggetto si ignora: la bolla resta, senza i dati in più.
      meta: meta is Map ? Map<String, dynamic>.from(meta) : const {},
      createdAt: createdAt,
    );
  }

  /// Come [ChatMessage.fromMap], ma una riga malformata dà null invece di fermare
  /// tutta la conversazione.
  static ChatMessage? tryFromMap(Map<String, dynamic> m) {
    try {
      return ChatMessage.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  /// Copia con qualche campo cambiato; [removeReply] toglie la citazione.
  ChatMessage copyWith({
    String? replyTo,
    bool removeReply = false,
    Uint8List? localImage,
    Uint8List? localAudio,
    bool? sending,
    bool? failed,
    bool? waiting,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    createdAt: createdAt,
    authorId: authorId,
    isSystem: isSystem,
    body: body,
    imagePath: imagePath,
    audioPath: audioPath,
    durationS: durationS,
    replayPath: replayPath,
    replyTo: removeReply ? null : replyTo ?? this.replyTo,
    expiresAt: expiresAt,
    expiredAt: expiredAt,
    meta: meta,
    localImage: localImage ?? this.localImage,
    localAudio: localAudio ?? this.localAudio,
    localReplay: localReplay,
    sending: sending ?? this.sending,
    failed: failed ?? this.failed,
    waiting: waiting ?? this.waiting,
  );
}

/// Ordine della conversazione: dal più recente (a parità d'ora decide l'id).
int compareNewestFirst(ChatMessage a, ChatMessage b) {
  final byTime = b.createdAt.compareTo(a.createdAt);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

final _random = Random.secure();

/// Id nuovo (uuid v4) per un messaggio: lo sceglie chi scrive, così il messaggio
/// mostrato subito si riconosce quando torna dal server (e un nuovo tentativo non
/// lo duplica).
String newMessageId() {
  final b = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Riepilogo di un canale per la lista: non letti e ultimo messaggio.
class ChannelOverview {
  const ChannelOverview({
    this.unread = 0,
    this.lastBody,
    this.lastAuthor,
    this.lastIsSystem = false,
    this.lastHasImage = false,
    this.lastHasAudio = false,
    this.lastType,
    this.lastAt,
  });

  final int unread;
  final String? lastBody;
  final String? lastAuthor;
  final bool lastIsSystem;
  final bool lastHasImage;
  final bool lastHasAudio;

  /// Tipo dell'ultimo messaggio (replay, announcement, formation...).
  final String? lastType;
  final DateTime? lastAt;

  String get preview {
    final empty = lastBody == null || lastBody!.isEmpty;
    final text = lastType == 'replay'
        ? '🎬 Schema con audio'
        : lastHasImage && empty
        ? 'Foto'
        : lastHasAudio && empty
        ? 'Messaggio vocale'
        : lastBody ?? '';
    if (lastIsSystem || lastAuthor == null) return text;
    return '$lastAuthor: $text';
  }
}

abstract class ChatRepository {
  Stream<List<Channel>> watchChannels();

  /// Gli ultimi [chatRecentLimit] messaggi del canale, dal più recente, in tempo
  /// reale. Come gli stream filtrati di Supabase non riceve le eliminazioni (arrivano
  /// da [watchDeletions]) e dopo una riconnessione può ripetere un messaggio.
  Stream<List<ChatMessage>> watchMessages(String channelId);

  /// Una pagina di messaggi creati fino a [before] compreso, dal più recente (per
  /// scorrere indietro): possono tornare messaggi già caricati, si tolgono per id.
  Future<List<ChatMessage>> olderMessages(
    String channelId,
    DateTime before, {
    int limit = chatPageSize,
  });

  /// Un messaggio (null se non c'è più): per le citazioni di messaggi non caricati.
  Future<ChatMessage?> message(String id);

  /// Gli ultimi [chatSearchLimit] messaggi che contengono [query] (maiuscole e
  /// minuscole non contano), dal più recente: solo nei canali che si vedono.
  Future<List<ChatMessage>> searchMessages(String query);

  /// Id dei messaggi eliminati da chiunque, in tempo reale (quelli eliminati da qui
  /// subito): una sola sottoscrizione per tutta l'app.
  Stream<String> watchDeletions();

  /// Non letti e ultimo messaggio per ogni canale (id del canale → riepilogo).
  Stream<Map<String, ChannelOverview>> watchOverview();

  /// Salva il messaggio e lo restituisce com'è sul server. [id] lo può scegliere chi
  /// scrive (vedi [newMessageId]).
  Future<ChatMessage> send(
    String channelId, {
    String? id,
    String? body,
    Uint8List? image,
    Uint8List? audio,
    int? durationS,
    Uint8List? replay,
    String? replyTo,
    Map<String, dynamic>? meta,
  });
  Future<void> delete(ChatMessage message);

  /// Segna il canale letto fino a [until]: l'ora (del server) del messaggio più
  /// recente visto, così non conta l'orologio del telefono.
  Future<void> markRead(String channelId, {DateTime? until});

  /// Ultima lettura del canale (per il separatore "Nuovi messaggi").
  Future<DateTime?> lastReadAt(String channelId);
  Future<Set<String>> mutedChannels();
  Future<void> setMuted(String channelId, bool muted);
  Future<String> imageUrl(String path);
  Future<String> audioUrl(String path);

  /// Il file delle azioni di un replay (JSON); null in demo se non è in memoria.
  Future<Uint8List?> replayBytes(ChatMessage message);

  /// Chiude gli stream interni.
  void dispose() {}
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = AppConfig.isDemo
      ? DemoChatRepository()
      : _SupabaseChatRepository(ref);
  ref.onDispose(repo.dispose);
  return repo;
});

// I dati della chat dipendono da chi è entrato (canali riservati, non letti, silenziati):
// con un altro account sullo stesso telefono si ricaricano da zero.

final channelsProvider = StreamProvider<List<Channel>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const []);
  return ref.watch(chatRepositoryProvider).watchChannels();
});

final chatOverviewProvider = StreamProvider<Map<String, ChannelOverview>>((
  ref,
) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const {});
  return ref.watch(chatRepositoryProvider).watchOverview();
});

/// Totale dei messaggi non letti (badge nel menu).
final chatUnreadProvider = Provider<int>(
  (ref) => (ref.watch(chatOverviewProvider).value ?? const {}).values.fold(
    0,
    (sum, o) => sum + o.unread,
  ),
);

final mutedChannelsProvider = FutureProvider<Set<String>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const {};
  return ref.watch(chatRepositoryProvider).mutedChannels();
});

/// Link firmato di una foto: resta in memoria finché serve (scorrendo la chat non si
/// riscarica) ma si rinnova prima delle 6 ore di validità.
final chatImageUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) async {
  ref.watch(currentUserIdProvider);
  final url = await ref.watch(chatRepositoryProvider).imageUrl(path);
  if (url.isEmpty || !ref.mounted) return url;
  final link = ref.keepAlive();
  final renew = Timer(chatImageUrlLifetime, () {
    ref.invalidateSelf();
    link.close();
  });
  ref.onDispose(renew.cancel);
  return url;
});

/// Link firmato di un vocale: si chiede solo per caricarlo nel lettore (pausa e
/// ripresa non lo chiedono) e, come quello delle foto, resta in memoria finché vale.
/// Si legge al tocco, senza ascoltarlo: resta in memoria da subito (altrimenti
/// sparirebbe prima di arrivare); un errore invece non resta, si riprova al tocco.
final chatAudioUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) async {
  ref.watch(currentUserIdProvider);
  final repo = ref.watch(chatRepositoryProvider);
  final link = ref.keepAlive();
  final String url;
  try {
    url = await repo.audioUrl(path);
  } catch (_) {
    link.close();
    rethrow;
  }
  if (!ref.mounted) return url;
  if (url.isEmpty) {
    link.close(); // demo: niente da tenere
    return url;
  }
  final renew = Timer(chatImageUrlLifetime, () {
    ref.invalidateSelf();
    link.close();
  });
  ref.onDispose(renew.cancel);
  return url;
});

/// Messaggio citato che non è tra quelli caricati (più vecchio): si chiede al server.
final quotedMessageProvider = FutureProvider.autoDispose
    .family<ChatMessage?, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(chatRepositoryProvider).message(id);
    });

/// Ricerca "Cerca nei messaggi" (la parola già ripulita dagli spazi ai lati).
final chatSearchProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, query) {
      ref.watch(currentUserIdProvider);
      return ref.watch(chatRepositoryProvider).searchMessages(query);
    });

class _SupabaseChatRepository extends ChatRepository {
  _SupabaseChatRepository(this._ref);
  final Ref _ref;
  final _refreshOverview = StreamController<void>.broadcast();
  late final _deletions = StreamController<String>.broadcast(
    onListen: _listenDeletions,
    onCancel: _stopDeletions,
  );
  RealtimeChannel? _deletionsChannel;
  var _deletionsTopic = 0;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  void dispose() {
    _refreshOverview.close();
    _stopDeletions();
    _deletions.close();
  }

  static List<ChatMessage> _parse(List<Map<String, dynamic>> rows) => [
    for (final r in rows) ?ChatMessage.tryFromMap(r),
  ];

  @override
  Stream<List<Channel>> watchChannels() => _client
      .from('channels')
      .stream(primaryKey: ['id'])
      .order('sort_order', ascending: true)
      .map((rows) => rows.map(Channel.fromMap).toList());

  @override
  Stream<List<ChatMessage>> watchMessages(String channelId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('channel_id', channelId)
      .order('created_at', ascending: false)
      .limit(chatRecentLimit)
      .map(_parse);

  @override
  Future<List<ChatMessage>> olderMessages(
    String channelId,
    DateTime before, {
    int limit = chatPageSize,
  }) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('channel_id', channelId)
        .lte('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);
    return _parse(rows);
  }

  @override
  Future<ChatMessage?> message(String id) async {
    final row = await _client
        .from('messages')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : ChatMessage.tryFromMap(row);
  }

  /// Le regole del database restituiscono solo i messaggi dei canali visibili.
  @override
  Future<List<ChatMessage>> searchMessages(String query) async {
    final q = query.trim();
    if (q.length < chatSearchMinLength) return const [];
    final rows = await _client
        .from('messages')
        .select()
        .ilike('body', '%${escapeLikePattern(q)}%')
        .order('created_at', ascending: false)
        .limit(chatSearchLimit);
    return _parse(rows);
  }

  /// Gli stream filtrati per canale non ricevono le eliminazioni (il tempo reale non
  /// può filtrarle): un solo abbonamento senza filtro per tutta l'app, che dei
  /// messaggi eliminati riceve solo l'id.
  void _listenDeletions() {
    _deletionsChannel = _client
        .channel('chat-eliminati-${_deletionsTopic++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final id = payload.oldRecord['id'];
            if (id is String) _deleted(id);
          },
        )
        .subscribe();
  }

  void _stopDeletions() {
    final channel = _deletionsChannel;
    _deletionsChannel = null;
    if (channel != null) unawaited(channel.unsubscribe());
  }

  void _deleted(String id) {
    if (!_deletions.isClosed) _deletions.add(id);
  }

  @override
  Stream<String> watchDeletions() => _deletions.stream;

  Future<Map<String, ChannelOverview>> _overview() async {
    final rows = await _client.rpc('chat_overview') as List;
    return {
      for (final r in rows.cast<Map<String, dynamic>>())
        r['channel_id'] as String: ChannelOverview(
          unread: (r['unread'] as num?)?.toInt() ?? 0,
          lastBody: r['last_body'] as String?,
          lastAuthor: r['last_author'] as String?,
          lastIsSystem: r['last_kind'] == 'system',
          lastHasImage: (r['last_has_image'] as bool?) ?? false,
          lastHasAudio: (r['last_has_audio'] as bool?) ?? false,
          lastType: r['last_type'] as String?,
          lastAt: r['last_at'] == null
              ? null
              : DateTime.parse(r['last_at'] as String).toLocal(),
        ),
    };
  }

  /// Si ricalcola a ogni nuovo messaggio (in tempo reale), a ogni eliminazione e dopo
  /// ogni lettura.
  @override
  Stream<Map<String, ChannelOverview>> watchOverview() {
    late final StreamController<Map<String, ChannelOverview>> out;
    final subs = <StreamSubscription<Object?>>[];
    Future<void> reload() async {
      try {
        final overview = await _overview();
        if (!out.isClosed) out.add(overview);
      } catch (e, st) {
        if (!out.isClosed) out.addError(e, st);
      }
    }

    out = StreamController(
      onListen: () {
        subs
          ..add(
            _client
                .from('messages')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false)
                .limit(1)
                .listen((_) => reload(), onError: (_) {}),
          )
          ..add(_refreshOverview.stream.listen((_) => reload()))
          ..add(watchDeletions().listen((_) => reload()));
        reload();
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  @override
  Future<ChatMessage> send(
    String channelId, {
    String? id,
    String? body,
    Uint8List? image,
    Uint8List? audio,
    int? durationS,
    Uint8List? replay,
    String? replyTo,
    Map<String, dynamic>? meta,
  }) async {
    final uid = _client.auth.currentUser!.id;
    // I file prendono il nome dall'id del messaggio: un nuovo tentativo ritrova
    // quelli già caricati invece di caricarne una seconda copia.
    final name = id ?? '${DateTime.now().microsecondsSinceEpoch}';
    final storage = _client.storage.from(chatBucket);
    final uploaded = <String>[];
    Future<String> upload(String path, Uint8List bytes, String type) async {
      try {
        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: type),
        );
      } on StorageException catch (e) {
        // Caricato da un tentativo precedente (nella propria cartella, con il
        // nome di questo messaggio): è lui, va bene così.
        final text = e.message.toLowerCase();
        if (e.statusCode != '409' &&
            !text.contains('already exists') &&
            !text.contains('duplicate')) {
          rethrow;
        }
      }
      uploaded.add(path);
      return path;
    }

    Future<void> removeUploaded() async {
      if (uploaded.isEmpty) return;
      try {
        await storage.remove(uploaded);
      } catch (_) {
        // Restano nella cartella di chi scrive: niente di grave.
      }
    }

    String? replayPath;
    String? imagePath;
    String? audioPath;
    try {
      if (replay != null) {
        replayPath = await upload(
          '$uid/$name.replay.json',
          replay,
          'application/json',
        );
      }
      if (image != null) {
        imagePath = await upload('$uid/$name.jpg', image, 'image/jpeg');
      }
      if (audio != null) {
        audioPath = await upload('$uid/$name.m4a', audio, 'audio/mp4');
      }
    } catch (_) {
      // Il messaggio non parte: i file già caricati non servono più.
      await removeUploaded();
      rethrow;
    }
    final Map<String, dynamic> saved;
    try {
      saved = await _client
          .from('messages')
          .insert({
            'id': ?id,
            'channel_id': channelId,
            'body': body,
            'image_path': imagePath,
            'audio_path': audioPath,
            'duration_s': audio == null
                ? null
                : (durationS ?? 1).clamp(
                    1,
                    replay == null ? maxVoiceSeconds : maxReplaySeconds,
                  ),
            'replay_path': replayPath,
            'reply_to': replyTo,
            'meta': meta,
          })
          .select()
          .single();
    } on PostgrestException {
      // Rifiutato dal database, quindi non salvato: via anche i file. Con un errore di
      // rete invece restano, perché il messaggio potrebbe essere arrivato lo stesso.
      await removeUploaded();
      rethrow;
    }
    return ChatMessage.fromMap(saved);
  }

  @override
  Future<void> delete(ChatMessage m) async {
    final rows = await _client
        .from('messages')
        .delete()
        .eq('id', m.id)
        .select('id');
    if (rows.isEmpty && await message(m.id) != null) {
      // Le regole del database non l'hanno eliminato (né tuo né del Direttivo).
      throw const AppError('Non puoi eliminare questo messaggio.');
    }
    // Sparisce subito da qui; agli altri arriva dall'abbonamento alle eliminazioni.
    _deleted(m.id);
    final files = [
      m.imagePath,
      m.audioPath,
      m.replayPath,
    ].whereType<String>().toList();
    if (files.isEmpty) return;
    try {
      await _client.storage.from(chatBucket).remove(files);
    } catch (_) {
      // Se l'allegato è di un altro e chi elimina non è del Direttivo (o la rete cade),
      // lo toglie la pulizia del server: il database lo mette in coda.
    }
  }

  @override
  Future<void> markRead(String channelId, {DateTime? until}) async {
    final at = until?.toUtc().toIso8601String();
    try {
      await _client.rpc(
        'mark_channel_read',
        params: {'p_channel': channelId, 'p_until': at},
      );
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      // Database senza la funzione nuova (migrazione non ancora applicata): come prima.
      await _client.from('channel_reads').upsert({
        'channel_id': channelId,
        'user_id': _client.auth.currentUser!.id,
        'last_read_at': at ?? DateTime.now().toUtc().toIso8601String(),
      });
    }
    if (!_refreshOverview.isClosed) _refreshOverview.add(null);
  }

  @override
  Future<DateTime?> lastReadAt(String channelId) async {
    final row = await _client
        .from('channel_reads')
        .select('last_read_at')
        .eq('channel_id', channelId)
        .eq('user_id', _client.auth.currentUser!.id)
        .maybeSingle();
    final v = row?['last_read_at'] as String?;
    return v == null ? null : DateTime.parse(v).toLocal();
  }

  @override
  Future<Set<String>> mutedChannels() async {
    final rows = await _client.from('channel_mutes').select('channel_id');
    return {for (final r in rows) r['channel_id'] as String};
  }

  @override
  Future<void> setMuted(String channelId, bool muted) async {
    final uid = _client.auth.currentUser!.id;
    if (muted) {
      await _client.from('channel_mutes').upsert({
        'channel_id': channelId,
        'user_id': uid,
      });
    } else {
      await _client
          .from('channel_mutes')
          .delete()
          .eq('channel_id', channelId)
          .eq('user_id', uid);
    }
  }

  @override
  Future<String> imageUrl(String path) =>
      _client.storage.from(chatBucket).createSignedUrl(path, 60 * 60 * 6);

  @override
  Future<String> audioUrl(String path) => imageUrl(path);

  @override
  Future<Uint8List?> replayBytes(ChatMessage m) async {
    final path = m.replayPath;
    if (path == null) return m.localReplay;
    return _client.storage.from(chatBucket).download(path);
  }
}

/// Chat in memoria per la demo e i test. Si comporta come Supabase: lo stream di un
/// canale riceve inserimenti e modifiche ma non le eliminazioni, che arrivano a parte
/// da [watchDeletions]; il database rifiuta la risposta a un messaggio che non c'è più.
class DemoChatRepository extends ChatRepository {
  /// [messages] al posto dei messaggi di esempio (per i test).
  DemoChatRepository({List<ChatMessage>? messages}) {
    final now = DateTime.now();
    if (messages != null) {
      _messages.addAll(messages);
      return;
    }
    _messages.addAll([
      ChatMessage(
        id: 'm5',
        channelId: 'c-main',
        authorId: 'p3',
        body: 'Il gol di ieri 🔥',
        expiresAt: now.subtract(const Duration(days: 1)),
        expiredAt: now.subtract(const Duration(hours: 5)),
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
      ChatMessage(
        id: 'm1',
        channelId: 'c-main',
        authorId: 'p2',
        body: 'Stasera tutti in lobby alle 21:15!',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      ChatMessage(
        id: 'm4',
        channelId: 'c-main',
        authorId: 'p2',
        audioPath: 'demo/voce.m4a',
        durationS: 12,
        createdAt: now.subtract(const Duration(hours: 2, minutes: 10)),
      ),
      ChatMessage(
        id: 'm2',
        channelId: 'c-main',
        authorId: 'p3',
        body: 'Ci sono 💪',
        replyTo: 'm1',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      ChatMessage(
        id: 'm3',
        channelId: 'c-milanac',
        authorId: 'p4',
        body: 'Stasera provo la build nuova da DC',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      ChatMessage(
        id: 'm6',
        channelId: 'c-tattiche',
        authorId: 'demo',
        body: 'Guardate come si difende in 11 contro 11: https://youtu.be/dQw4w9WgXcQ',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      ChatMessage(
        id: 'm7',
        channelId: 'c-tattiche',
        authorId: 'demo',
        durationS: 20,
        localReplay: demoReplay().toBytes(),
        meta: {
          'type': 'replay',
          'title': 'Uscita dal basso',
          'board': demoReplay().initial.toPreviewJson(),
          'duration_ms': 20000,
        },
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
    ]);
    // Generale letto fino a 2 ore e mezza fa: gli ultimi due messaggi sono nuovi.
    _reads['c-main'] = now.subtract(const Duration(hours: 2, minutes: 30));
  }

  static const _channels = [
    Channel(
      id: 'c-main',
      slug: 'main',
      name: 'Generale',
      description: 'La chat di tutto il club',
      icon: 'forum',
    ),
    Channel(
      id: 'c-milanac',
      slug: 'milanac',
      name: 'Milan AC',
      description: 'La chat della prima squadra',
      icon: 'team',
      team: 'milanac',
    ),
    Channel(
      id: 'c-futuro',
      slug: 'futuro',
      name: 'Milan AC Futuro',
      description: 'La chat del Futuro',
      icon: 'team',
      team: 'futuro',
    ),
    Channel(
      id: 'c-tattiche',
      slug: 'tattiche',
      name: 'Tattiche & Schemi',
      description: 'Idee, schemi e video',
      icon: 'tattiche',
    ),
    Channel(
      id: 'c-comunicazioni',
      slug: 'comunicazioni',
      name: 'Comunicazioni',
      description:
          'Avvisi ufficiali del Direttivo: formazioni, eventi, regolamento',
      icon: 'campaign',
      direttivoWrites: true,
    ),
    Channel(
      id: 'c-direttivo',
      slug: 'direttivo',
      name: 'Sala Direttivo',
      description: 'Solo per il Direttivo: decisioni, mercato, formazioni',
      icon: 'direttivo',
      direttivoOnly: true,
    ),
  ];

  final _messages = <ChatMessage>[];
  final _reads = <String, DateTime>{};
  final _muted = <String>{};

  /// Messaggi inseriti o modificati (come gli eventi del tempo reale).
  final _rows = StreamController<ChatMessage>.broadcast();

  /// Id dei messaggi eliminati (come l'abbonamento senza filtro alle eliminazioni).
  final _deletions = StreamController<String>.broadcast();

  /// Qualcosa è cambiato: si ricalcola il riepilogo dei canali.
  final _changes = StreamController<void>.broadcast();
  var _next = 100;

  List<ChatMessage> _of(String channelId) =>
      _messages.where((m) => m.channelId == channelId).toList()
        ..sort(compareNewestFirst);

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Un messaggio nuovo o modificato arriva a chi segue il suo canale (con
  /// [realtime] false no: il telefono è scollegato).
  void _saved(ChatMessage m, {bool realtime = true}) {
    final i = _messages.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      _messages[i] = m;
    } else {
      _messages.add(m);
    }
    if (realtime && !_rows.isClosed) _rows.add(m);
    _changed();
  }

  void _remove(String id, {required bool realtime}) {
    _messages.removeWhere((m) => m.id == id);
    // Come nel database (on delete set null): le risposte perdono il riferimento.
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].replyTo != id) continue;
      _messages[i] = _messages[i].copyWith(removeReply: true);
      if (realtime && !_rows.isClosed) _rows.add(_messages[i]);
    }
    if (realtime && !_deletions.isClosed) _deletions.add(id);
    _changed();
  }

  /// Solo demo e test: arriva il messaggio [m] scritto da un altro. Con [realtime]
  /// false arriva solo sul server (connessione caduta): lo stream aperto non lo
  /// riceve, lo trova solo riconnettendosi.
  void receive(ChatMessage m, {bool realtime = true}) =>
      _saved(m, realtime: realtime);

  /// Solo demo e test: il messaggio [id] lo elimina un altro (o il server, come
  /// l'annuncio delle carte rifatto). Con [realtime] false l'eliminazione non arriva
  /// al telefono (connessione caduta): lo scopre solo chiedendo al server.
  void deleteElsewhere(String id, {bool realtime = true}) =>
      _remove(id, realtime: realtime);

  Map<String, ChannelOverview> _overview() => {
    for (final c in _channels)
      c.id: () {
        final list = _of(c.id);
        final read = _reads[c.id];
        final last = list.firstOrNull;
        return ChannelOverview(
          unread: list
              .where(
                (m) =>
                    m.authorId != 'demo' &&
                    (read == null || m.createdAt.isAfter(read)),
              )
              .length,
          lastBody: last?.body,
          lastAuthor: last == null ? null : _names[last.authorId],
          lastIsSystem: last?.isSystem ?? false,
          lastHasImage: last?.hasImage ?? false,
          lastHasAudio: last?.hasAudio ?? false,
          lastType: last == null || last.systemType.isEmpty
              ? null
              : last.systemType,
          lastAt: last?.createdAt,
        );
      }(),
  };

  static const _names = {
    'demo': 'Demo Direttivo',
    'p2': 'Marco Rossi',
    'p3': 'Luca Bianchi',
    'p4': 'Andrea Neri',
  };

  @override
  Stream<List<Channel>> watchChannels() async* {
    yield _channels;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String channelId) {
    // Come lo stream filtrato di Supabase: parte dagli ultimi messaggi del canale,
    // aggiunge quelli nuovi e modificati e non sa nulla delle eliminazioni.
    final rows = <String, ChatMessage>{};
    StreamSubscription<ChatMessage>? sub;
    late final StreamController<List<ChatMessage>> out;
    void emit() => out.add(
      (rows.values.toList()..sort(compareNewestFirst))
          .take(chatRecentLimit)
          .toList(),
    );
    out = StreamController(
      onListen: () {
        for (final m in _of(channelId).take(chatRecentLimit)) {
          rows[m.id] = m;
        }
        sub = _rows.stream.where((m) => m.channelId == channelId).listen((m) {
          rows[m.id] = m;
          emit();
        });
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<List<ChatMessage>> olderMessages(
    String channelId,
    DateTime before, {
    int limit = chatPageSize,
  }) async =>
      _of(channelId)
          .where((m) => !m.createdAt.isAfter(before))
          .take(limit)
          .toList();

  @override
  Future<ChatMessage?> message(String id) async =>
      _messages.where((m) => m.id == id).firstOrNull;

  @override
  Future<List<ChatMessage>> searchMessages(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < chatSearchMinLength) return const [];
    final visible = {for (final c in _channels) c.id};
    return (_messages
            .where(
              (m) =>
                  visible.contains(m.channelId) &&
                  (m.body ?? '').toLowerCase().contains(q),
            )
            .toList()
          ..sort(compareNewestFirst))
        .take(chatSearchLimit)
        .toList();
  }

  @override
  Stream<String> watchDeletions() => _deletions.stream;

  @override
  Stream<Map<String, ChannelOverview>> watchOverview() async* {
    yield _overview();
    yield* _changes.stream.map((_) => _overview());
  }

  @override
  Future<ChatMessage> send(
    String channelId, {
    String? id,
    String? body,
    Uint8List? image,
    Uint8List? audio,
    int? durationS,
    Uint8List? replay,
    String? replyTo,
    Map<String, dynamic>? meta,
  }) async {
    // Come il database: si risponde solo a un messaggio (ancora presente) del canale.
    if (replyTo != null &&
        !_messages.any((m) => m.id == replyTo && m.channelId == channelId)) {
      throw const PostgrestException(
        message: 'Si può rispondere solo a un messaggio dello stesso canale',
        code: 'P0001',
      );
    }
    if (id != null && _messages.any((m) => m.id == id)) {
      throw const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
    }
    final m = ChatMessage(
      id: id ?? 'm${_next++}',
      channelId: channelId,
      authorId: 'demo',
      body: body,
      localImage: image,
      localAudio: audio,
      localReplay: replay,
      durationS: audio == null && replay == null ? null : durationS,
      replyTo: replyTo,
      meta: meta ?? const {},
      createdAt: DateTime.now(),
    );
    _saved(m);
    return m;
  }

  @override
  Future<void> delete(ChatMessage m) async => _remove(m.id, realtime: true);

  @override
  Future<void> markRead(String channelId, {DateTime? until}) async {
    final at = until ?? DateTime.now();
    final before = _reads[channelId];
    // Come mark_channel_read: mai all'indietro.
    if (before == null || at.isAfter(before)) _reads[channelId] = at;
    _changed();
  }

  @override
  Future<DateTime?> lastReadAt(String channelId) async => _reads[channelId];

  @override
  Future<Set<String>> mutedChannels() async => Set.of(_muted);

  @override
  Future<void> setMuted(String channelId, bool muted) async =>
      muted ? _muted.add(channelId) : _muted.remove(channelId);

  @override
  Future<String> imageUrl(String path) async => '';

  @override
  Future<String> audioUrl(String path) async => '';

  @override
  Future<Uint8List?> replayBytes(ChatMessage m) async => m.localReplay;

  @override
  void dispose() {
    _rows.close();
    _deletions.close();
    _changes.close();
  }
}
