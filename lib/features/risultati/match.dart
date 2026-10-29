import 'dart:typed_data';

import '../../core/italian_time.dart';
import '../../core/teams.dart';

enum MatchKind {
  torneo('Torneo'),
  amichevole('Amichevole');

  const MatchKind(this.label);
  final String label;
}

enum MatchOutcome { vittoria, pareggio, sconfitta, daGiocare }

/// Partita ufficiale o amichevole (tabella `matches`).
class ClubMatch {
  const ClubMatch({
    required this.id,
    required this.kind,
    required this.opponent,
    required this.playedAt,
    this.competition,
    this.home = true,
    this.goalsFor,
    this.goalsAgainst,
    this.scorers,
    this.notes,
    this.team = Team.milanac,
    this.tournamentId,
    this.goalkeeperId,
    this.createdAt,
    this.timeline = const [],
  });

  final String id;
  final MatchKind kind;

  /// I gol con il minuto (facoltativi, in ordine di minuto): tabellone, timeline e
  /// cronaca come in una diretta TV. Non più dei gol del risultato.
  final List<MatchGoal> timeline;

  /// Portiere della partita (dalla formazione pubblicata, correggibile dal Direttivo):
  /// serve per la carta blu elettrico delle tre partite senza subire gol.
  final String? goalkeeperId;

  /// Squadra del club che ha giocato.
  final Team team;

  /// Torneo di appartenenza (facoltativo).
  final String? tournamentId;
  final String opponent;

  /// Quando si gioca, in ora italiana: anno, mese, giorno, ore e minuti come in Italia
  /// (vedi [italianClock]), come gli eventi del calendario. Si confronta solo con altre
  /// ore italiane.
  final DateTime playedAt;

  /// Quando è stata inserita (null = non ancora salvata): due partite della stessa sera
  /// hanno lo stesso orario e vale l'ordine di inserimento.
  final DateTime? createdAt;
  final String? competition;
  final bool home;
  final int? goalsFor;
  final int? goalsAgainst;
  final String? scorers;
  final String? notes;

  MatchOutcome get outcome {
    if (goalsFor == null || goalsAgainst == null) return MatchOutcome.daGiocare;
    if (goalsFor! > goalsAgainst!) return MatchOutcome.vittoria;
    if (goalsFor! < goalsAgainst!) return MatchOutcome.sconfitta;
    return MatchOutcome.pareggio;
  }

  factory ClubMatch.fromMap(Map<String, dynamic> m) => ClubMatch(
    id: m['id'] as String,
    kind: MatchKind.values.byName(m['kind'] as String),
    opponent: m['opponent'] as String,
    playedAt: italianClock(DateTime.parse(m['played_at'] as String)),
    competition: m['competition'] as String?,
    home: (m['home'] as bool?) ?? true,
    goalsFor: (m['goals_for'] as num?)?.toInt(),
    goalsAgainst: (m['goals_against'] as num?)?.toInt(),
    scorers: m['scorers'] as String?,
    notes: m['notes'] as String?,
    team: Team.parse(m['team']) ?? Team.milanac,
    tournamentId: m['tournament_id'] as String?,
    goalkeeperId: m['goalkeeper_id'] as String?,
    createdAt: switch (m['created_at']) {
      final String v => DateTime.parse(v),
      _ => null,
    },
    // Prima della migrazione 0027 la colonna non c'è: nessun minuto.
    timeline: sortedGoals([
      for (final g in (m['timeline'] as List?) ?? const [])
        ?MatchGoal.tryParse(g),
    ]),
  );

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'opponent': opponent,
    'played_at': fromItalianClock(playedAt).toIso8601String(),
    'competition': competition,
    'home': home,
    'goals_for': goalsFor,
    'goals_against': goalsAgainst,
    'scorers': scorers,
    'notes': notes,
    'team': team.name,
    'tournament_id': kind == MatchKind.torneo ? tournamentId : null,
    'goalkeeper_id': goalkeeperId,
    'timeline': [for (final g in timeline) g.toJson()],
  };
}

/// Un gol con il minuto: del club ([ours], con il marcatore scritto come nei marcatori)
/// o degli avversari.
class MatchGoal {
  const MatchGoal({required this.minute, required this.ours, this.scorer});
  final int minute;
  final bool ours;
  final String? scorer;

  /// Minuti possibili: dal primo ai supplementari con recupero.
  static const maxMinute = 130;

  static MatchGoal? tryParse(Object? json) {
    if (json is! Map) return null;
    final minute = json['minute'];
    final side = json['side'];
    if (minute is! num || minute < 1 || minute > maxMinute) return null;
    if (side != 'us' && side != 'them') return null;
    final scorer = json['scorer'];
    return MatchGoal(
      minute: minute.toInt(),
      ours: side == 'us',
      scorer: side == 'us' && scorer is String && scorer.trim().isNotEmpty
          ? scorer.trim()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'minute': minute,
    'side': ours ? 'us' : 'them',
    if (ours && scorer != null) 'scorer': scorer,
  };

  @override
  bool operator ==(Object other) =>
      other is MatchGoal &&
      other.minute == minute &&
      other.ours == ours &&
      other.scorer == scorer;

  @override
  int get hashCode => Object.hash(minute, ours, scorer);
}

/// I gol in ordine di minuto (a pari minuto, come sono stati scritti).
List<MatchGoal> sortedGoals(Iterable<MatchGoal> goals) {
  final indexed = goals.indexed.toList()
    ..sort((a, b) {
      final byMinute = a.$2.minute.compareTo(b.$2.minute);
      return byMinute != 0 ? byMinute : a.$1.compareTo(b.$1);
    });
  return [for (final (_, g) in indexed) g];
}

/// Il punteggio dopo ogni gol della [timeline] (club, avversari): 1–0, 1–1, 2–1...
List<(int, int)> runningScore(List<MatchGoal> timeline) {
  var us = 0, them = 0;
  return [for (final g in timeline) g.ours ? (++us, them) : (us, ++them)];
}

final _neverCreated = DateTime.utc(1970);

/// Dalla partita più recente: orario, poi ordine di inserimento, poi id (come la giornata
/// sul server, `(played_at, created_at, id)`). Due partite della stessa sera hanno lo
/// stesso orario (l'editor le salva alle 21:30): l'ultima inserita è l'ultimo risultato.
int newestMatchFirst(ClubMatch a, ClubMatch b) {
  final played = b.playedAt.compareTo(a.playedAt);
  if (played != 0) return played;
  final created = (b.createdAt ?? _neverCreated).compareTo(
    a.createdAt ?? _neverCreated,
  );
  return created != 0 ? created : b.id.compareTo(a.id);
}

final _matchday = RegExp(r'(\d+)\s*[ªa°]?\s*giornata', caseSensitive: false);

/// La giornata scritta nella competizione ("FVPA Serie B – 2ª giornata" → "2ª giornata").
String? matchdayOf(ClubMatch m) {
  final c = m.competition;
  final found = c == null ? null : _matchday.firstMatch(c);
  return found == null ? null : '${found.group(1)}ª giornata';
}

enum MediaType { link, video, photo }

/// Foto, clip (max 15s) o link allegato a una partita (tabella `match_media`).
class MatchMedia {
  const MatchMedia({
    required this.id,
    required this.matchId,
    required this.type,
    this.url,
    this.storagePath,
    this.durationS,
    this.caption,
    this.localBytes,
  });

  final String id;
  final String matchId;
  final MediaType type;
  final String? url;
  final String? storagePath;
  final int? durationS;
  final String? caption;

  /// Solo modalità demo: contenuto tenuto in memoria invece che su Supabase Storage.
  final Uint8List? localBytes;

  // Uguaglianza per id: evita di richiedere di nuovo l'URL firmato a ogni aggiornamento.
  @override
  bool operator ==(Object other) => other is MatchMedia && other.id == id;

  @override
  int get hashCode => id.hashCode;

  factory MatchMedia.fromMap(Map<String, dynamic> m) => MatchMedia(
    id: m['id'] as String,
    matchId: m['match_id'] as String,
    type: MediaType.values.byName(m['type'] as String),
    url: m['url'] as String?,
    storagePath: m['storage_path'] as String?,
    durationS: (m['duration_s'] as num?)?.toInt(),
    caption: m['caption'] as String?,
  );
}

/// Estrae l'ID di un video YouTube (per mostrare l'anteprima), se il link è di YouTube.
String? youtubeId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.host.contains('youtu.be')) {
    return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  }
  if (uri.host.contains('youtube.com')) {
    if (uri.queryParameters['v'] != null) return uri.queryParameters['v'];
    final i = uri.pathSegments.indexWhere(
      (s) => s == 'shorts' || s == 'embed' || s == 'live',
    );
    if (i >= 0 && i + 1 < uri.pathSegments.length) {
      return uri.pathSegments[i + 1];
    }
  }
  return null;
}

/// Bilancio della stagione.
class MatchRecord {
  MatchRecord(Iterable<ClubMatch> matches) {
    for (final m in matches) {
      switch (m.outcome) {
        case MatchOutcome.vittoria:
          wins++;
        case MatchOutcome.pareggio:
          draws++;
        case MatchOutcome.sconfitta:
          losses++;
        case MatchOutcome.daGiocare:
          continue;
      }
      goalsFor += m.goalsFor!;
      goalsAgainst += m.goalsAgainst!;
    }
  }

  int wins = 0, draws = 0, losses = 0, goalsFor = 0, goalsAgainst = 0;
  int get played => wins + draws + losses;
}
