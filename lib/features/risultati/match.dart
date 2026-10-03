import 'dart:typed_data';

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
  });

  final String id;
  final MatchKind kind;

  /// Squadra del club che ha giocato.
  final Team team;

  /// Torneo di appartenenza (facoltativo).
  final String? tournamentId;
  final String opponent;
  final DateTime playedAt;
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
    playedAt: DateTime.parse(m['played_at'] as String).toLocal(),
    competition: m['competition'] as String?,
    home: (m['home'] as bool?) ?? true,
    goalsFor: (m['goals_for'] as num?)?.toInt(),
    goalsAgainst: (m['goals_against'] as num?)?.toInt(),
    scorers: m['scorers'] as String?,
    notes: m['notes'] as String?,
    team: Team.parse(m['team']) ?? Team.milanac,
    tournamentId: m['tournament_id'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'opponent': opponent,
    'played_at': playedAt.toUtc().toIso8601String(),
    'competition': competition,
    'home': home,
    'goals_for': goalsFor,
    'goals_against': goalsAgainst,
    'scorers': scorers,
    'notes': notes,
    'team': team.name,
    'tournament_id': kind == MatchKind.torneo ? tournamentId : null,
  };
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
