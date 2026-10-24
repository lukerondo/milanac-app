import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config.dart';
import 'chat_repository.dart';

/// I messaggi scritti e non ancora salvati dal server, tenuti sul telefono: se l'app
/// si chiude (o il telefono si spegne) mentre partono, alla riapertura ripartono da
/// soli, foto e vocali compresi. Divisi per account.
abstract class ChatOutbox {
  /// I messaggi in attesa di [userId] (di un canale, o di tutti), dal più vecchio.
  Future<List<ChatMessage>> pending(String userId, {String? channelId});

  /// Salva (o aggiorna) un messaggio in attesa.
  Future<void> put(String userId, ChatMessage message);

  /// Il messaggio è partito (o l'utente l'ha tolto): non serve più.
  Future<void> remove(String userId, String messageId);
}

final chatOutboxProvider = Provider<ChatOutbox>(
  (ref) => AppConfig.isDemo || kIsWeb ? MemoryChatOutbox() : FileChatOutbox(),
);

/// In memoria: demo, web e test (sul web la pagina non sopravvive comunque).
class MemoryChatOutbox implements ChatOutbox {
  final _byUser = <String, Map<String, ChatMessage>>{};

  @override
  Future<List<ChatMessage>> pending(String userId, {String? channelId}) async =>
      [
        for (final m in (_byUser[userId] ?? const {}).values)
          if (channelId == null || m.channelId == channelId) m,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> put(String userId, ChatMessage message) async =>
      (_byUser[userId] ??= {})[message.id] = message;

  @override
  Future<void> remove(String userId, String messageId) async =>
      _byUser[userId]?.remove(messageId);
}

/// Sul telefono: una cartella per account con, per ogni messaggio, un file JSON
/// (testo, canale, citazione, ora) e gli allegati accanto. Le operazioni vanno in
/// fila una alla volta: un "partito" non arriva mai prima del suo salvataggio.
class FileChatOutbox implements ChatOutbox {
  FileChatOutbox({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;
  Future<void> _queue = Future.value();

  static const _attachments = {'foto', 'vocale', 'replay'};

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Directory> _dir(String userId) async {
    final root = await _root();
    return Directory(
      [root.path, 'chat_in_uscita', _safe(userId)].join(Platform.pathSeparator),
    );
  }

  File _file(Directory dir, String id, String kind) =>
      File('${dir.path}${Platform.pathSeparator}${_safe(id)}.$kind');

  /// Gli id sono uuid: tutto il resto si toglie, così il nome resta un nome di file.
  static String _safe(String s) => s.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '');

  @override
  Future<List<ChatMessage>> pending(String userId, {String? channelId}) =>
      _serial(() async {
        final dir = await _dir(userId);
        if (!await dir.exists()) return const <ChatMessage>[];
        final found = <ChatMessage>[];
        await for (final entry in dir.list()) {
          if (entry is! File || !entry.path.endsWith('.json')) continue;
          try {
            final data = jsonDecode(await entry.readAsString());
            if (data is! Map<String, dynamic>) continue;
            final id = data['id'] as String;
            if (channelId != null && data['channel_id'] != channelId) continue;
            Future<Uint8List?> read(String kind) async {
              final f = _file(dir, id, kind);
              return await f.exists() ? f.readAsBytes() : null;
            }

            found.add(
              _fromJson(
                data,
                image: data['foto'] == true ? await read('foto') : null,
                audio: data['vocale'] == true ? await read('vocale') : null,
                replay: data['replay'] == true ? await read('replay') : null,
              ),
            );
          } catch (_) {
            // File rovinato (app chiusa a metà scrittura): si lascia stare.
          }
        }
        return found..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

  @override
  Future<void> put(String userId, ChatMessage m) => _serial(() async {
    final dir = await _dir(userId);
    await dir.create(recursive: true);
    // Prima gli allegati, poi il JSON (scritto a parte e rinominato): un messaggio
    // a metà non risulta mai in attesa.
    final files = {
      'foto': m.localImage,
      'vocale': m.localAudio,
      'replay': m.localReplay,
    };
    for (final MapEntry(:key, :value) in files.entries) {
      if (value != null) await _file(dir, m.id, key).writeAsBytes(value);
    }
    final json = _file(dir, m.id, 'json');
    final temp = File('${json.path}.tmp');
    await temp.writeAsString(jsonEncode(_toJson(m)), flush: true);
    await temp.rename(json.path);
  });

  @override
  Future<void> remove(String userId, String id) => _serial(() async {
    final dir = await _dir(userId);
    for (final kind in ['json', ..._attachments]) {
      final f = _file(dir, id, kind);
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  });

  static Map<String, dynamic> _toJson(ChatMessage m) => {
    'id': m.id,
    'channel_id': m.channelId,
    'author_id': m.authorId,
    'body': m.body,
    'duration_s': m.durationS,
    'reply_to': m.replyTo,
    'meta': m.meta,
    'created_at': m.createdAt.toUtc().toIso8601String(),
    'foto': m.localImage != null,
    'vocale': m.localAudio != null,
    'replay': m.localReplay != null,
  };

  static ChatMessage _fromJson(
    Map<String, dynamic> d, {
    Uint8List? image,
    Uint8List? audio,
    Uint8List? replay,
  }) {
    final meta = d['meta'];
    return ChatMessage(
      id: d['id'] as String,
      channelId: d['channel_id'] as String,
      authorId: d['author_id'] as String?,
      body: d['body'] as String?,
      durationS: (d['duration_s'] as num?)?.toInt(),
      replyTo: d['reply_to'] as String?,
      meta: meta is Map ? Map<String, dynamic>.from(meta) : const {},
      createdAt: DateTime.parse(d['created_at'] as String).toLocal(),
      localImage: image,
      localAudio: audio,
      localReplay: replay,
      failed: true,
    );
  }
}
