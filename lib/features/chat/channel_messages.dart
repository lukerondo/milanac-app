import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import 'chat_outbox.dart';
import 'chat_repository.dart';

/// La conversazione caricata di un canale.
class ChannelHistory {
  const ChannelHistory({
    this.messages = const [],
    this.deleted = const {},
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
    this.gap = false,
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

  /// Dopo una riconnessione con molte novità mancano messaggi tra quelli già visti
  /// e i più recenti: si recuperano a pagine e, finché mancano, il canale non si
  /// segna letto (si segnerebbero anche quelli mai caricati).
  final bool gap;
}

/// Com'è andato un invio: [error] se il messaggio non è partito e aspetta l'utente
/// (resta "non inviato" nella conversazione e si riprova toccandolo); [waiting] se
/// non è partito per la rete e ripartirà da solo; [quoteDropped] se è partito senza
/// citazione perché il messaggio citato è stato eliminato nel frattempo.
typedef SendReport = ({Object? error, bool quoteDropped, bool waiting});

const SendReport _nothingToReport = (
  error: null,
  quoteDropped: false,
  waiting: false,
);

/// All'avvio (e a ogni cambio di account) i canali con messaggi rimasti in uscita sul
/// telefono si aprono in sottofondo: ripartono senza entrare nella conversazione.
final chatOutboxResumerProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;
  final outbox = ref.watch(chatOutboxProvider);
  var alive = true;
  ref.onDispose(() => alive = false);
  unawaited(() async {
    try {
      final pending = await outbox.pending(userId);
      if (!alive) return;
      for (final channelId in {for (final m in pending) m.channelId}) {
        // La conversazione si tiene in vita da sola finché ha messaggi in uscita.
        ref.read(messagesProvider(channelId));
      }
    } catch (_) {
      // Cartella illeggibile: si recupera aprendo le conversazioni.
    }
  }());
});

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

  /// La pagina precedente in arrivo: chi la chiede di nuovo aspetta quella.
  Future<void>? _pending;

  /// Una pagina intera di messaggi già visti con la stessa ora: si va oltre.
  DateTime? _stuckAt;

  /// Cambia con l'account e quando si riparte dai più recenti (buco dopo una
  /// riconnessione): le pagine chieste prima si scartano.
  int _generation = 0;

  /// L'ora dell'ultimo messaggio visto prima di un buco (vedi [_checkGap]): quelli
  /// dopo, fino ai più recenti caricati, si stanno recuperando. Null se non manca
  /// niente.
  DateTime? _gapAfter;
  bool _catchingUp = false;

  /// Pagine recuperate di fila per chiudere un buco: se ne mancano di più, il resto
  /// arriva scorrendo in cima (o alla prossima novità).
  static const _catchUpPages = 10;

  /// Se le pagine del buco non arrivano (rete instabile) e nel canale non arriva
  /// nessuna novità che rilanci il recupero, si riprova da soli dopo 5, 10, 30 secondi
  /// (poi ogni 30): finché manca qualcosa il canale non si segna letto.
  static const _catchUpRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];
  Timer? _catchUpRetry;
  int _catchUpFailures = 0;

  /// La conversazione resta in memoria, anche uscendo dalla pagina, finché un
  /// messaggio scritto qui sta partendo o non è partito: al ritorno lo si ritrova.
  KeepAliveLink? _hold;

  /// Gli invii partono uno alla volta, nell'ordine in cui sono stati scritti.
  Future<void> _queue = Future.value();

  /// I messaggi in uscita salvati sul telefono: ripartono anche dopo aver chiuso
  /// l'app (o se il telefono si spegne).
  late ChatOutbox _outbox;

  /// L'account di cui si sono già riletti i messaggi in uscita dal telefono.
  String? _restoredFor;

  /// La rilettura è in corso: intanto la conversazione resta in memoria.
  var _restoring = false;

  /// Nuovi tentativi da soli dei messaggi fermi per la rete: dopo 2, 5, 15, 30
  /// secondi (poi ogni 30), e subito quando dal server arriva qualcosa.
  static const autoRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];
  Timer? _autoRetry;
  var _autoRetryFailures = 0;

  @override
  Stream<ChannelHistory> build() {
    final userId = ref.watch(currentUserIdProvider);
    final repo = ref.watch(chatRepositoryProvider);
    _outbox = ref.watch(chatOutboxProvider);
    // Ricostruendo (nuovo tentativo del tempo reale) Riverpod lascia cadere i
    // "tieni in memoria" di prima: si riprende qui sotto, se serve.
    _hold = null;
    if (userId != _userId) {
      // Un altro account sullo stesso telefono: si riparte da zero.
      _userId = userId;
      _known.clear();
      _deleted.clear();
      _unconfirmed.clear();
      _hasMore = null;
      _loadingMore = false;
      _loadMoreFailed = false;
      _pending = null;
      _stuckAt = null;
      _gapAfter = null;
      _generation++;
      _autoRetry?.cancel();
      _autoRetry = null;
      _autoRetryFailures = 0;
      _restoredFor = null;
      _restoring = false;
    }
    final restore = userId != null && _restoredFor != userId;
    if (restore) {
      _restoredFor = userId;
      _restoring = true;
    }
    _holdWhilePending();
    if (userId == null) return Stream.value(const ChannelHistory());
    if (restore) unawaited(_restore(userId));
    // Senza nessuno che guarda (pagina chiusa con un messaggio in sospeso) Riverpod
    // mette lo stream in pausa: niente copie accumulate, l'ultima arriva alla ripresa.
    final out = _out = StreamController<ChannelHistory>(onResume: _emit);
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
      _catchUpRetry?.cancel();
      _catchUpRetry = null;
      _autoRetry?.cancel();
      _autoRetry = null;
      out.close();
    });
    return out.stream;
  }

  void _emit() {
    _holdWhilePending();
    final out = _out;
    if (out == null || out.isClosed || out.isPaused) return;
    out.add(
      ChannelHistory(
        messages: _known.values.toList()..sort(compareNewestFirst),
        deleted: Set.of(_deleted),
        hasMore: _hasMore ?? false,
        loadingMore: _loadingMore,
        loadMoreFailed: _loadMoreFailed,
        gap: _gapAfter != null,
      ),
    );
  }

  void _holdWhilePending() {
    if (!ref.mounted) return;
    if (_restoring || _known.values.any((m) => m.isLocal)) {
      _hold ??= ref.keepAlive();
    } else {
      _hold?.close();
      _hold = null;
    }
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
      if (rows.length >= chatRecentLimit) _checkGap(ids, oldest);
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
        // Arrivato dal server prima della risposta all'invio: sul telefono non
        // serve più.
        if (_known[m.id]?.isLocal ?? false) _forget(m.id);
        _known[m.id] = _merge(_known[m.id], m);
        _unconfirmed.remove(m.id);
      }
    }
    _hasMore ??= rows.length >= chatRecentLimit;
    // Un buco ancora aperto (anche se il recupero non era riuscito) si recupera ora:
    // una novità dal server vuol dire che la rete c'è.
    final recover = _gapAfter != null && !_catchingUp;
    if (recover) _loadMoreFailed = false;
    _emit();
    if (recover) unawaited(_catchUp());
    // Per lo stesso motivo ripartono subito i messaggi fermi per la rete.
    _retryWaiting();
  }

  /// Una pagina intera di più recenti senza nessuno di quelli già visti: dopo una
  /// riconnessione ne sono arrivati più di una pagina, e quelli in mezzo non
  /// arriverebbero né dallo stream né scorrendo in cima (le pagine partono dal più
  /// vecchio caricato). Si tengono solo i più recenti e si recupera all'indietro.
  void _checkGap(Set<String> ids, DateTime oldest) {
    DateTime? lastSeen;
    for (final m in _known.values) {
      // I propri appena inviati non dicono che cosa è arrivato prima di loro.
      if (m.isLocal || _unconfirmed.contains(m.id)) continue;
      if (ids.contains(m.id)) return; // si sovrappongono: niente buco
      final at = m.createdAt;
      if (at.isBefore(oldest) && (lastSeen == null || at.isAfter(lastSeen))) {
        lastSeen = at;
      }
    }
    if (lastSeen == null) return;
    _known.removeWhere(
      (id, m) =>
          !m.isLocal && !ids.contains(id) && !m.createdAt.isAfter(oldest),
    );
    _unconfirmed.removeWhere((id) => !_known.containsKey(id));
    final gap = _gapAfter;
    _gapAfter = gap != null && gap.isBefore(lastSeen) ? gap : lastSeen;
    _hasMore = true;
    _stuckAt = null;
    _loadingMore = false;
    _loadMoreFailed = false;
    _pending = null;
    _generation++;
  }

  /// Recupera all'indietro i messaggi del buco, una pagina dopo l'altra.
  Future<void> _catchUp() async {
    if (_catchingUp) return;
    _catchingUp = true;
    try {
      for (var i = 0; i < _catchUpPages; i++) {
        if (!ref.mounted ||
            _gapAfter == null ||
            _hasMore != true ||
            _loadMoreFailed) {
          return;
        }
        await loadMore();
      }
    } finally {
      _catchingUp = false;
      _retryCatchUpLater();
    }
  }

  void _retryCatchUpLater() {
    _catchUpRetry?.cancel();
    _catchUpRetry = null;
    if (!ref.mounted || _gapAfter == null || !_loadMoreFailed) {
      _catchUpFailures = 0;
      return;
    }
    final delays = _catchUpRetryDelays;
    final delay = delays[math.min(_catchUpFailures, delays.length - 1)];
    _catchUpFailures++;
    _catchUpRetry = Timer(delay, () {
      _catchUpRetry = null;
      if (!ref.mounted || _gapAfter == null || _catchingUp) return;
      _loadMoreFailed = false;
      _emit();
      unawaited(_catchUp());
    });
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
  Future<void> loadMore() {
    if (_hasMore != true) return Future.value();
    final pending = _pending;
    if (pending != null) return pending;
    final load = _pending = _loadPage();
    unawaited(
      load.whenComplete(() {
        if (identical(_pending, load)) _pending = null;
      }),
    );
    return load;
  }

  Future<void> _loadPage() async {
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
      // Le pagine sono arrivate fino all'ultimo messaggio visto prima del buco.
      final gap = _gapAfter;
      if (gap != null &&
          (page.length < chatPageSize ||
              page.any((m) => !m.createdAt.isAfter(gap)))) {
        _gapAfter = null;
      }
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
    // Sul telefono finché il server non lo salva: riparte anche dopo aver chiuso
    // l'app.
    final user = _userId;
    if (user != null) unawaited(_outbox.put(user, m).catchError((Object _) {}));
    return _enqueue(m);
  }

  /// Riprova subito un messaggio non partito o fermo per la rete (con lo stesso id:
  /// se in realtà era arrivato, non si duplica).
  Future<SendReport> retry(String id) {
    final m = _known[id];
    if (m == null || !(m.failed || m.waiting)) {
      return Future.value(_nothingToReport);
    }
    final again = m.copyWith(sending: true, failed: false, waiting: false);
    _known[id] = again;
    _emit();
    return _enqueue(again);
  }

  /// Toglie dalla conversazione (e dal telefono) un messaggio non partito.
  void discard(String id) {
    final m = _known[id];
    if (m == null || !(m.failed || m.waiting)) return;
    _known.remove(id);
    _forget(id);
    _stopAutoRetryIfIdle();
    _emit();
  }

  /// I messaggi rimasti in uscita sul telefono (app chiusa mentre partivano):
  /// ricompaiono nella conversazione e ripartono da soli.
  Future<void> _restore(String userId) async {
    try {
      final saved = await _outbox.pending(userId, channelId: channelId);
      if (!ref.mounted || _userId != userId) return;
      var found = false;
      for (final m in saved) {
        final known = _known[m.id];
        if (known != null || _deleted.contains(m.id)) {
          // Già arrivato dal server (la risposta si era persa): non serve più.
          if (known == null || !known.isLocal) _forget(m.id);
          continue;
        }
        _known[m.id] = m.copyWith(sending: false, failed: false, waiting: true);
        found = true;
      }
      // Prima dei più recenti dal server la conversazione non si mostra (sembrerebbe
      // vuota): i recuperati arrivano con loro.
      if (found) _retryWaiting(show: _hasMore != null);
    } catch (_) {
      // Cartella illeggibile: non c'è niente da recuperare.
    } finally {
      if (ref.mounted && _userId == userId) {
        _restoring = false;
        _holdWhilePending();
      }
    }
  }

  void _forget(String id) {
    final user = _userId;
    if (user != null) {
      unawaited(_outbox.remove(user, id).catchError((Object _) {}));
    }
  }

  /// Rimanda subito, in ordine, i messaggi fermi per la rete.
  void _retryWaiting({bool show = true}) {
    final waiting = _known.values.where((m) => m.waiting).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (waiting.isEmpty) return;
    _autoRetry?.cancel();
    _autoRetry = null;
    for (final m in waiting) {
      final again = m.copyWith(sending: true, waiting: false);
      _known[m.id] = again;
      unawaited(_enqueue(again));
    }
    if (show) _emit();
  }

  /// Il prossimo tentativo da solo, sempre più distanziato finché la rete manca.
  void _scheduleAutoRetry() {
    if (_autoRetry != null || !ref.mounted) return;
    final delays = autoRetryDelays;
    final delay = delays[math.min(_autoRetryFailures, delays.length - 1)];
    _autoRetryFailures++;
    _autoRetry = Timer(delay, () {
      _autoRetry = null;
      if (ref.mounted) _retryWaiting();
    });
  }

  Future<SendReport> _enqueue(ChatMessage m) {
    final repo = ref.read(chatRepositoryProvider);
    final report = _queue.then((_) => _deliver(repo, m));
    _queue = report.then((_) {}, onError: (Object _) {});
    return report;
  }

  Future<SendReport> _deliver(ChatRepository repo, ChatMessage m) async {
    // Uno scritto prima aspetta la rete: si aspetta con lui, così i messaggi
    // arrivano nell'ordine in cui sono stati scritti.
    if (_known.values.any(
      (o) => o.waiting && o.id != m.id && o.createdAt.isBefore(m.createdAt),
    )) {
      _put(m.copyWith(sending: false, waiting: true));
      _scheduleAutoRetry();
      return (error: null, quoteDropped: false, waiting: true);
    }
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
        return (error: null, quoteDropped: quoteDropped, waiting: false);
      } catch (e) {
        if (e is PostgrestException && e.code == '23505') {
          // Era già arrivato (si era persa la risposta): niente doppione.
          _sent(message, null);
          return (error: null, quoteDropped: quoteDropped, waiting: false);
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
        if (isTransientError(e)) {
          // Rete assente o server occupato: riparte da solo (anche dopo aver
          // chiuso l'app), senza chiedere niente a nessuno.
          _put(message.copyWith(sending: false, waiting: true));
          _scheduleAutoRetry();
          return (error: null, quoteDropped: quoteDropped, waiting: true);
        }
        _put(message.copyWith(sending: false, failed: true));
        return (error: e, quoteDropped: quoteDropped, waiting: false);
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
        ? local.copyWith(sending: false, failed: false, waiting: false)
        : _merge(local, saved);
    _unconfirmed.add(local.id);
    _forget(local.id);
    // La rete c'è: i prossimi tentativi ripartono dal primo intervallo.
    _autoRetryFailures = 0;
    _stopAutoRetryIfIdle();
    _emit();
  }

  /// Nessun messaggio aspetta più la rete: il prossimo tentativo non serve.
  void _stopAutoRetryIfIdle() {
    if (_known.values.any((m) => m.waiting)) return;
    _autoRetry?.cancel();
    _autoRetry = null;
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
