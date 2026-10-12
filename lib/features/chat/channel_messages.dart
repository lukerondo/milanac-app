import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import 'chat_repository.dart';

/// La conversazione caricata di un canale.
class ChannelHistory {
  const ChannelHistory({
    this.messages = const [],
    this.deleted = const {},
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  /// Dal più recente al più vecchio, senza doppioni.
  final List<ChatMessage> messages;

  /// Messaggi eliminati mentre la conversazione era aperta: le loro citazioni
  /// diventano "Messaggio non più disponibile".
  final Set<String> deleted;

  /// Sul server ci sono messaggi più vecchi, da caricare scorrendo in cima.
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
}

/// Com'è andato un invio: [error] se il messaggio non è partito (resta "non inviato"
/// nella conversazione e si riprova toccandolo); [quoteDropped] se è partito senza
/// citazione perché il messaggio citato è stato eliminato nel frattempo.
typedef SendReport = ({Object? error, bool quoteDropped});

/// I messaggi di un canale: i più recenti in tempo reale, i precedenti a pagine
/// scorrendo in cima, quelli appena scritti subito (prima che il server li salvi) e
/// senza quelli eliminati, anche da altri (lo stream del canale non lo sa).
final messagesProvider = StreamNotifierProvider.autoDispose
    .family<ChannelMessages, ChannelHistory, String>(ChannelMessages.new);

class ChannelMessages extends StreamNotifier<ChannelHistory> {
  ChannelMessages(this.channelId);
  final String channelId;

  /// Tutti i messaggi conosciuti, per id: un messaggio ripetuto dallo stream (dopo una
  /// riconnessione) o arrivato sia dallo stream sia da una pagina compare una volta.
  final _known = <String, ChatMessage>{};

  /// Eliminati: lo stream del canale continua a riportarli, si scartano.
  final _deleted = <String>{};

  /// Inviati da qui e salvati, ma non ancora arrivati dallo stream (tempo reale lento
  /// o giù): restano anche se mancano dall'elenco dei più recenti.
  final _unconfirmed = <String>{};

  StreamController<ChannelHistory>? _out;
  String? _userId;

  /// Messaggi più vecchi sul server: null finché non arriva il primo elenco.
  bool? _hasMore;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  /// Una pagina intera di messaggi già visti con la stessa ora: si va oltre.
  DateTime? _stuckAt;
  int _generation = 0;

  /// Gli invii partono uno alla volta, nell'ordine in cui sono stati scritti.
  Future<void> _queue = Future.value();

  @override
  Stream<ChannelHistory> build() {
    final userId = ref.watch(currentUserIdProvider);
    final repo = ref.watch(chatRepositoryProvider);
    if (userId != _userId) {
      // Un altro account sullo stesso telefono: si riparte da zero.
      _userId = userId;
      _known.clear();
      _deleted.clear();
      _unconfirmed.clear();
      _hasMore = null;
      _loadingMore = false;
      _loadMoreFailed = false;
      _stuckAt = null;
      _generation++;
    }
    if (userId == null) return Stream.value(const ChannelHistory());
    final out = _out = StreamController<ChannelHistory>();
    var failed = false;
    final subs = <StreamSubscription<Object>>[
      repo.watchDeletions().listen(_onDeleted, onError: (Object _) {}),
      // Un errore del tempo reale fa ripartire lo stream (nuovi tentativi del
      // provider) senza perdere quello che si vede.
      repo
          .watchMessages(channelId)
          .listen(
            _onRecent,
            onError: (Object e, StackTrace st) {
              failed = true;
              out.addError(e, st);
            },
            onDone: () {
              // Chiuso dal server senza errore: si riapre, altrimenti la conversazione
              // smetterebbe di aggiornarsi senza dirlo.
              if (!failed && !out.isClosed) {
                out.addError(const AppError('Conversazione non aggiornata'));
              }
            },
          ),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      out.close();
    });
    return out.stream;
  }

  void _emit() {
    final out = _out;
    if (out == null || out.isClosed) return;
    out.add(
      ChannelHistory(
        messages: _known.values.toList()..sort(compareNewestFirst),
        deleted: Set.of(_deleted),
        hasMore: _hasMore ?? false,
        loadingMore: _loadingMore,
        loadMoreFailed: _loadMoreFailed,
      ),
    );
  }

  /// I più recenti dallo stream del canale.
  void _onRecent(List<ChatMessage> rows) {
    final fresh = [
      for (final m in rows)
        if (!_deleted.contains(m.id)) m,
    ];
    if (fresh.isNotEmpty) {
      final ids = {for (final m in fresh) m.id};
      final oldest = fresh
          .map((m) => m.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      // Un messaggio che conoscevamo manca tra i più recenti pur essendo più nuovo
      // del più vecchio di loro: è stato eliminato mentre lo stream era scollegato
      // (riconnettendosi ricarica dal server, ma le eliminazioni perse non arrivano).
      _known.removeWhere(
        (id, m) =>
            !ids.contains(id) &&
            !m.isLocal &&
            !_unconfirmed.contains(id) &&
            m.createdAt.isAfter(oldest),
      );
      for (final m in fresh) {
        _known[m.id] = _merge(_known[m.id], m);
        _unconfirmed.remove(m.id);
      }
    }
    _hasMore ??= rows.length >= chatRecentLimit;
    _emit();
  }

  /// Il messaggio [m] dal server al posto di quello che c'era ([old]).
  static ChatMessage _merge(ChatMessage? old, ChatMessage m) {
    if (old == null) return m;
    // Quando il messaggio citato viene eliminato il database toglie il riferimento:
    // nella conversazione aperta la citazione resta, come "non più disponibile".
    final lostQuote = m.replyTo == null && !old.isLocal ? old.replyTo : null;
    return m.copyWith(
      replyTo: lostQuote,
      // Foto e vocale appena inviati da qui: restano quelli in memoria (niente download).
      localImage: m.imagePath == null ? null : old.localImage,
      localAudio: m.audioPath == null ? null : old.localAudio,
    );
  }

  void _onDeleted(String id) {
    _deleted.add(id);
    _unconfirmed.remove(id);
    if (_known.remove(id) != null) _emit();
  }

  /// La pagina di messaggi precedenti (scorrendo in cima alla conversazione).
  Future<void> loadMore() async {
    if (_loadingMore || _hasMore != true) return;
    final server = _known.values.where((m) => !m.isLocal);
    if (server.isEmpty) return;
    final oldest = server
        .map((m) => m.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final generation = _generation;
    _loadingMore = true;
    _loadMoreFailed = false;
    _emit();
    try {
      // Fino all'ora del più vecchio compresa, e un millisecondo oltre (il web non ha
      // i microsecondi): i messaggi con la stessa ora non si perdono, i doppioni si
      // tolgono per id. Se una pagina intera era già nota si va oltre quell'ora.
      final before = _stuckAt == oldest
          ? oldest.subtract(const Duration(milliseconds: 1))
          : oldest.add(const Duration(milliseconds: 1));
      final page = await ref
          .read(chatRepositoryProvider)
          .olderMessages(channelId, before);
      if (generation != _generation) return;
      var added = 0;
      for (final m in page) {
        if (_deleted.contains(m.id) || _known.containsKey(m.id)) continue;
        _known[m.id] = m;
        added++;
      }
      if (page.length < chatPageSize) _hasMore = false;
      _stuckAt = added == 0 ? oldest : null;
    } catch (_) {
      if (generation == _generation) _loadMoreFailed = true;
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        _emit();
      }
    }
  }

  /// Scrive un messaggio: compare subito ("in invio") e diventa quello del server
  /// appena salvato, anche se il tempo reale è giù.
  Future<SendReport> send({
    String? body,
    Uint8List? image,
    Uint8List? audio,
    int? durationS,
    String? replyTo,
  }) {
    final m = ChatMessage(
      id: newMessageId(),
      channelId: channelId,
      authorId: ref.read(currentUserIdProvider),
      body: body,
      localImage: image,
      localAudio: audio,
      durationS: audio == null ? null : durationS,
      replyTo: replyTo,
      createdAt: DateTime.now(),
      sending: true,
    );
    _known[m.id] = m;
    _emit();
    return _enqueue(m);
  }

  /// Riprova un messaggio non partito (con lo stesso id: se in realtà era arrivato,
  /// non si duplica).
  Future<SendReport> retry(String id) {
    final m = _known[id];
    if (m == null || !m.failed) {
      return Future.value((error: null, quoteDropped: false));
    }
    final again = m.copyWith(sending: true, failed: false);
    _known[id] = again;
    _emit();
    return _enqueue(again);
  }

  /// Toglie dalla conversazione un messaggio non partito.
  void discard(String id) {
    if (!(_known[id]?.failed ?? false)) return;
    _known.remove(id);
    _emit();
  }

  Future<SendReport> _enqueue(ChatMessage m) {
    final repo = ref.read(chatRepositoryProvider);
    final report = _queue.then((_) => _deliver(repo, m));
    _queue = report.then((_) {}, onError: (Object _) {});
    return report;
  }

  Future<SendReport> _deliver(ChatRepository repo, ChatMessage m) async {
    var message = m;
    var quoteDropped = false;
    while (true) {
      try {
        final saved = await repo.send(
          channelId,
          id: message.id,
          body: message.body,
          image: message.localImage,
          audio: message.localAudio,
          durationS: message.durationS,
          replyTo: message.replyTo,
        );
        _sent(message, saved);
        return (error: null, quoteDropped: quoteDropped);
      } catch (e) {
        if (e is PostgrestException && e.code == '23505') {
          // Era già arrivato (si era persa la risposta): niente doppione.
          _sent(message, null);
          return (error: null, quoteDropped: quoteDropped);
        }
        final quote = message.replyTo;
        if (quote != null && !await _exists(repo, quote)) {
          // Il messaggio citato è stato eliminato e il database rifiuta la risposta:
          // si invia senza citazione (un vocale non va perso).
          quoteDropped = true;
          message = message.copyWith(removeReply: true);
          _put(message);
          continue;
        }
        _put(message.copyWith(sending: false, failed: true));
        return (error: e, quoteDropped: quoteDropped);
      }
    }
  }

  Future<bool> _exists(ChatRepository repo, String id) async {
    try {
      return await repo.message(id) != null;
    } catch (_) {
      return true; // senza rete non si sa: resta "non inviato" e si riproverà
    }
  }

  /// Salvato dal server ([saved]; null se c'era già).
  void _sent(ChatMessage local, ChatMessage? saved) {
    final current = _known[local.id];
    // Tolto nel frattempo (cambio di account) o già arrivato dallo stream.
    if (current == null || !current.isLocal) return;
    _known[local.id] = saved == null
        ? local.copyWith(sending: false, failed: false)
        : _merge(local, saved);
    _unconfirmed.add(local.id);
    _emit();
  }

  /// Aggiorna un messaggio ancora locale (non se nel frattempo è arrivato dal server:
  /// per esempio salvato anche se la risposta si è persa).
  void _put(ChatMessage m) {
    final current = _known[m.id];
    if (current == null || !current.isLocal) return;
    _known[m.id] = m;
    _emit();
  }
}
