import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';

const chatBucket = 'chat';

/// Canale della chat (tabella `channels`).
class Channel {
  const Channel({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.icon = 'chat',
    this.direttivoOnly = false,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String icon;

  /// Canale riservato al Direttivo (Sala Direttivo).
  final bool direttivoOnly;

  IconData get iconData => switch (icon) {
    'forum' => Icons.forum_rounded,
    'presenze' => Icons.how_to_reg_rounded,
    'fantacalcio' => Icons.emoji_events_rounded,
    'tattiche' => Icons.draw_rounded,
    'direttivo' => Icons.admin_panel_settings_rounded,
    _ => Icons.chat_rounded,
  };

  factory Channel.fromMap(Map<String, dynamic> m) => Channel(
    id: m['id'] as String,
    slug: m['slug'] as String,
    name: m['name'] as String,
    description: m['description'] as String?,
    icon: (m['icon'] as String?) ?? 'chat',
    direttivoOnly: (m['direttivo_only'] as bool?) ?? false,
  );
}

/// Messaggio (tabella `messages`). I messaggi "system" sono scritti dal database
/// (es. ritardi e assenze nel canale Presenze).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.createdAt,
    this.authorId,
    this.isSystem = false,
    this.body,
    this.imagePath,
    this.meta = const {},
    this.localImage,
  });

  final String id;
  final String channelId;
  final String? authorId;
  final bool isSystem;
  final String? body;
  final String? imagePath;
  final Map<String, dynamic> meta;
  final DateTime createdAt;

  /// Solo demo: foto tenuta in memoria.
  final Uint8List? localImage;

  bool get hasImage => imagePath != null || localImage != null;

  /// Avviso ufficiale del Direttivo (evidenziato in chat, titolo dedicato nella notifica).
  bool get isAnnouncement => meta['type'] == 'announcement';

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: m['id'] as String,
    channelId: m['channel_id'] as String,
    authorId: m['author_id'] as String?,
    isSystem: m['kind'] == 'system',
    body: m['body'] as String?,
    imagePath: m['image_path'] as String?,
    meta: (m['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );
}

/// Riepilogo di un canale per la lista: non letti e ultimo messaggio.
class ChannelOverview {
  const ChannelOverview({
    this.unread = 0,
    this.lastBody,
    this.lastAuthor,
    this.lastIsSystem = false,
    this.lastHasImage = false,
    this.lastAt,
  });

  final int unread;
  final String? lastBody;
  final String? lastAuthor;
  final bool lastIsSystem;
  final bool lastHasImage;
  final DateTime? lastAt;

  String get preview {
    final text = lastHasImage && (lastBody == null || lastBody!.isEmpty)
        ? 'Foto'
        : lastBody ?? '';
    if (lastIsSystem || lastAuthor == null) return text;
    return '$lastAuthor: $text';
  }
}

abstract class ChatRepository {
  Stream<List<Channel>> watchChannels();

  /// Ultimi messaggi del canale, dal più recente.
  Stream<List<ChatMessage>> watchMessages(String channelId);

  /// Non letti e ultimo messaggio per ogni canale (id del canale → riepilogo).
  Stream<Map<String, ChannelOverview>> watchOverview();
  Future<void> send(
    String channelId, {
    String? body,
    Uint8List? image,
    Map<String, dynamic>? meta,
  });
  Future<void> delete(ChatMessage message);
  Future<void> markRead(String channelId);
  Future<Set<String>> mutedChannels();
  Future<void> setMuted(String channelId, bool muted);
  Future<String> imageUrl(String path);

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

final channelsProvider = StreamProvider<List<Channel>>(
  (ref) => ref.watch(chatRepositoryProvider).watchChannels(),
);

final messagesProvider = StreamProvider.family<List<ChatMessage>, String>(
  (ref, channelId) =>
      ref.watch(chatRepositoryProvider).watchMessages(channelId),
);

final chatOverviewProvider = StreamProvider<Map<String, ChannelOverview>>(
  (ref) => ref.watch(chatRepositoryProvider).watchOverview(),
);

/// Totale dei messaggi non letti (badge nel menu).
final chatUnreadProvider = Provider<int>(
  (ref) => (ref.watch(chatOverviewProvider).value ?? const {}).values.fold(
    0,
    (sum, o) => sum + o.unread,
  ),
);

final mutedChannelsProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(chatRepositoryProvider).mutedChannels(),
);

final chatImageUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref.watch(chatRepositoryProvider).imageUrl(path),
);

class _SupabaseChatRepository extends ChatRepository {
  _SupabaseChatRepository(this._ref);
  final Ref _ref;
  final _refreshOverview = StreamController<void>.broadcast();

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  void dispose() => _refreshOverview.close();

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
      .limit(200)
      .map((rows) => rows.map(ChatMessage.fromMap).toList());

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
          lastAt: r['last_at'] == null
              ? null
              : DateTime.parse(r['last_at'] as String).toLocal(),
        ),
    };
  }

  /// Si ricalcola a ogni nuovo messaggio (in tempo reale) e dopo ogni lettura.
  @override
  Stream<Map<String, ChannelOverview>> watchOverview() {
    late final StreamController<Map<String, ChannelOverview>> out;
    final subs = <StreamSubscription<Object?>>[];
    Future<void> reload() async {
      try {
        if (!out.isClosed) out.add(await _overview());
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
          ..add(_refreshOverview.stream.listen((_) => reload()));
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
  Future<void> send(
    String channelId, {
    String? body,
    Uint8List? image,
    Map<String, dynamic>? meta,
  }) async {
    String? path;
    if (image != null) {
      path =
          '${_client.auth.currentUser!.id}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await _client.storage
          .from(chatBucket)
          .uploadBinary(
            path,
            image,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    }
    await _client.from('messages').insert({
      'channel_id': channelId,
      'body': body,
      'image_path': path,
      'meta': meta,
    });
  }

  @override
  Future<void> delete(ChatMessage m) async {
    await _client.from('messages').delete().eq('id', m.id);
    if (m.imagePath != null) {
      // Se la foto è di un altro e chi elimina non è del Direttivo, resta nel bucket.
      await _client.storage.from(chatBucket).remove([m.imagePath!]);
    }
  }

  @override
  Future<void> markRead(String channelId) async {
    await _client.from('channel_reads').upsert({
      'channel_id': channelId,
      'user_id': _client.auth.currentUser!.id,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    });
    _refreshOverview.add(null);
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
}

/// Chat in memoria per la demo e i test.
class DemoChatRepository extends ChatRepository {
  DemoChatRepository() {
    final now = DateTime.now();
    _messages.addAll([
      ChatMessage(
        id: 'm1',
        channelId: 'c-main',
        authorId: 'p2',
        body: 'Stasera tutti in lobby alle 21:15!',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      ChatMessage(
        id: 'm2',
        channelId: 'c-main',
        authorId: 'p3',
        body: 'Ci sono 💪',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      ChatMessage(
        id: 'm3',
        channelId: 'c-presenze',
        authorId: 'p3',
        isSystem: true,
        body: 'Luca Bianchi stasera arriva in ritardo, alle 21:50 · Esco tardi da lavoro',
        meta: const {'type': 'attendance', 'status': 'ritardo'},
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
    ]);
  }

  static const _channels = [
    Channel(
      id: 'c-main',
      slug: 'main',
      name: 'MILANAC Main',
      description: 'Il canale di tutto il club',
      icon: 'forum',
    ),
    Channel(
      id: 'c-presenze',
      slug: 'presenze',
      name: 'Presenze',
      description: 'Ritardi e assenze arrivano qui in automatico',
      icon: 'presenze',
    ),
    Channel(
      id: 'c-fanta',
      slug: 'fantacalcio',
      name: 'Fantacalcio',
      description: 'Aste, scambi e sfottò',
      icon: 'fantacalcio',
    ),
    Channel(
      id: 'c-tattiche',
      slug: 'tattiche',
      name: 'Tattiche & Schemi',
      description: 'Idee, schemi e video',
      icon: 'tattiche',
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
  final _changes = StreamController<void>.broadcast();
  var _next = 100;

  List<ChatMessage> _of(String channelId) =>
      _messages.where((m) => m.channelId == channelId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
          lastAt: last?.createdAt,
        );
      }(),
  };

  static const _names = {
    'demo': 'Demo Direttivo',
    'p2': 'Marco Rossi',
    'p3': 'Luca Bianchi',
  };

  @override
  Stream<List<Channel>> watchChannels() async* {
    yield _channels;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String channelId) async* {
    yield _of(channelId);
    yield* _changes.stream.map((_) => _of(channelId));
  }

  @override
  Stream<Map<String, ChannelOverview>> watchOverview() async* {
    yield _overview();
    yield* _changes.stream.map((_) => _overview());
  }

  @override
  Future<void> send(
    String channelId, {
    String? body,
    Uint8List? image,
    Map<String, dynamic>? meta,
  }) async {
    _messages.add(
      ChatMessage(
        id: 'm${_next++}',
        channelId: channelId,
        authorId: 'demo',
        body: body,
        localImage: image,
        meta: meta ?? const {},
        createdAt: DateTime.now(),
      ),
    );
    _changes.add(null);
  }

  @override
  Future<void> delete(ChatMessage m) async {
    _messages.removeWhere((x) => x.id == m.id);
    _changes.add(null);
  }

  @override
  Future<void> markRead(String channelId) async {
    _reads[channelId] = DateTime.now();
    _changes.add(null);
  }

  @override
  Future<Set<String>> mutedChannels() async => Set.of(_muted);

  @override
  Future<void> setMuted(String channelId, bool muted) async =>
      muted ? _muted.add(channelId) : _muted.remove(channelId);

  @override
  Future<String> imageUrl(String path) async => '';

  @override
  void dispose() => _changes.close();
}
