import 'chat_repository.dart';

/// Un sondaggio in chat: la domanda è il testo del messaggio, le opzioni stanno nel
/// meta (`{"type": "poll", "options": [...], "multiple": false, "closed_at": ...}`).
class ChatPoll {
  const ChatPoll({
    required this.question,
    required this.options,
    this.multiple = false,
    this.closedAt,
  });

  /// Gli stessi limiti del database (migrazione 0030).
  static const minOptions = 2;
  static const maxOptions = 10;
  static const maxOptionLength = 80;
  static const maxQuestionLength = 300;

  final String question;
  final List<String> options;

  /// Si possono scegliere più opzioni.
  final bool multiple;

  /// Chiuso da chi l'ha creato o dal Direttivo: non si vota più.
  final DateTime? closedAt;
  bool get closed => closedAt != null;

  /// Il sondaggio del messaggio [m]; null se non è un sondaggio o se il meta non torna
  /// (il meta è libero: si legge senza fidarsi).
  static ChatPoll? of(ChatMessage m) {
    final meta = m.meta;
    if (meta['type'] != 'poll' || !m.hasText) return null;
    final raw = meta['options'];
    if (raw is! List || raw.length < minOptions || raw.length > maxOptions) {
      return null;
    }
    final options = [
      for (final o in raw)
        if (o is String && o.trim().isNotEmpty) o.trim(),
    ];
    if (options.length != raw.length) return null;
    final closed = meta['closed_at'];
    return ChatPoll(
      question: m.body!.trim(),
      options: options,
      multiple: meta['multiple'] == true,
      closedAt: closed is String ? DateTime.tryParse(closed)?.toLocal() : null,
    );
  }

  /// Il meta da salvare con il messaggio.
  static Map<String, dynamic> meta(
    List<String> options, {
    bool multiple = false,
  }) => {
    'type': 'poll',
    'options': [for (final o in options) o.trim()],
    'multiple': multiple,
  };

  /// Che cosa non va nelle opzioni scritte (null se si può creare): come il database,
  /// da 2 a 10, diverse tra loro (maiuscole e spazi non contano).
  static String? problemWith(String question, List<String> options) {
    if (question.trim().isEmpty) return 'Scrivi la domanda.';
    final filled = [
      for (final o in options)
        if (o.trim().isNotEmpty) o.trim().toLowerCase(),
    ];
    if (filled.length < minOptions) return 'Servono almeno due risposte.';
    if (filled.toSet().length != filled.length) {
      return 'Due risposte sono uguali.';
    }
    return null;
  }
}

/// Il voto di una persona (tabella `poll_votes`): le opzioni scelte, vuoto se l'ha
/// ritirato.
class PollVote {
  const PollVote({
    required this.messageId,
    required this.userId,
    this.options = const {},
  });

  final String messageId;
  final String userId;
  final Set<int> options;

  static PollVote? tryFromMap(Map<String, dynamic> m) {
    final message = m['message_id'], user = m['user_id'], raw = m['options'];
    if (message is! String || user is! String) return null;
    return PollVote(
      messageId: message,
      userId: user,
      options: {
        if (raw is List)
          for (final o in raw)
            if (o is num) o.toInt(),
      },
    );
  }
}

/// I risultati del sondaggio: per ogni opzione chi l'ha scelta, quanti hanno votato e
/// che cosa ha scelto [me].
class PollTally {
  factory PollTally(ChatPoll poll, Iterable<PollVote> votes, {String? me}) {
    final voters = [for (final _ in poll.options) <String>[]];
    var total = 0;
    var mine = const <int>{};
    for (final v in votes) {
      final valid = {
        for (final o in v.options)
          if (o >= 0 && o < poll.options.length) o,
      };
      if (valid.isEmpty) continue;
      total++;
      if (v.userId == me) mine = valid;
      for (final o in valid) {
        voters[o].add(v.userId);
      }
    }
    return PollTally._(voters, total, mine);
  }

  const PollTally._(this.voters, this.total, this.mine);

  /// Per ogni opzione, chi l'ha scelta.
  final List<List<String>> voters;

  /// Quante persone hanno votato.
  final int total;

  /// Le opzioni scelte da me (vuoto se non ho votato).
  final Set<int> mine;

  bool get voted => mine.isNotEmpty;

  int count(int option) => voters[option].length;

  /// La parte di chi ha votato che ha scelto [option] (da 0 a 1).
  double share(int option) => total == 0 ? 0 : count(option) / total;

  /// Le opzioni più votate (vuoto se nessuno ha votato).
  Set<int> get leaders {
    var best = 0;
    for (final v in voters) {
      if (v.length > best) best = v.length;
    }
    if (best == 0) return const {};
    return {
      for (var i = 0; i < voters.length; i++)
        if (voters[i].length == best) i,
    };
  }

  /// "Nessun voto", "1 voto", "5 voti".
  String get totalLabel => switch (total) {
    0 => 'Nessun voto',
    1 => '1 voto',
    _ => '$total voti',
  };
}
