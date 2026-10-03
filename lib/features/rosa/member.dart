import '../../core/auth/profile.dart';
import '../../core/teams.dart';

/// Un membro della rosa (riga della tabella `profiles`).
class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.gamertag,
    this.fieldPosition,
    this.shirtNumber,
    this.avatarUrl,
    this.active = true,
    this.requestedRole = ClubRole.giocatore,
    this.teams = const {Team.milanac},
    this.overall,
    this.playStyle,
    this.platform,
  });

  final String id;
  final String displayName;
  final ClubRole role;
  final DateTime joinedAt;
  final String? gamertag;
  final String? fieldPosition;
  final int? shirtNumber;
  final String? avatarUrl;
  final bool active;

  /// Ruolo chiesto dall'utente al primo accesso.
  final ClubRole requestedRole;

  /// Squadre in cui gioca: le assegna il Direttivo.
  final Set<Team> teams;

  /// Carta FUT: overall (40–99) scelto dal giocatore, stile di gioco e piattaforma.
  final int? overall;
  final String? playStyle;
  final GamePlatform? platform;

  bool inTeam(Team? team) => team == null || teams.contains(team);

  String get roleLabel => switch (role) {
    ClubRole.direttivo => 'Direttivo',
    ClubRole.giocatore => 'Giocatore',
    ClubRole.pending => 'In attesa',
  };

  Member copyWith({
    String? displayName,
    ClubRole? role,
    DateTime? joinedAt,
    String? gamertag,
    String? fieldPosition,
    int? shirtNumber,
    bool? active,
    Set<Team>? teams,
    int? overall,
    String? playStyle,
    GamePlatform? platform,
  }) => Member(
    id: id,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    joinedAt: joinedAt ?? this.joinedAt,
    gamertag: gamertag ?? this.gamertag,
    fieldPosition: fieldPosition ?? this.fieldPosition,
    shirtNumber: shirtNumber ?? this.shirtNumber,
    avatarUrl: avatarUrl,
    active: active ?? this.active,
    requestedRole: requestedRole,
    teams: teams ?? this.teams,
    overall: overall ?? this.overall,
    playStyle: playStyle ?? this.playStyle,
    platform: platform ?? this.platform,
  );

  factory Member.fromMap(Map<String, dynamic> m) => Member(
    id: m['id'] as String,
    displayName: (m['display_name'] as String?) ?? 'Giocatore',
    gamertag: m['gamertag'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    fieldPosition: m['field_position'] as String?,
    shirtNumber: (m['shirt_number'] as num?)?.toInt(),
    joinedAt: DateTime.parse(m['joined_at'] as String),
    active: (m['active'] as bool?) ?? true,
    role: parseRole(m['club_role'], ClubRole.pending),
    requestedRole: parseRole(m['requested_role'], ClubRole.giocatore),
    teams: Team.parseSet(m['teams']),
    overall: (m['overall'] as num?)?.toInt(),
    playStyle: m['play_style'] as String?,
    platform: GamePlatform.values.asNameMap()[m['platform']],
  );

  /// Campi modificabili dal Direttivo.
  Map<String, dynamic> toUpdateMap() => {
    'display_name': displayName,
    'gamertag': gamertag,
    'club_role': role.name,
    'joined_at': joinedAt.toIso8601String().substring(0, 10),
    'active': active,
    'teams': teamsToJson(teams),
    ...cardMap(),
  };

  /// Campi della carta, modificabili anche dal giocatore sul proprio profilo.
  Map<String, dynamic> cardMap() => {
    'overall': overall,
    'play_style': playStyle,
    'platform': platform?.name,
    'field_position': fieldPosition,
    'shirt_number': shirtNumber,
  };
}

enum GamePlatform {
  ps5('PlayStation 5'),
  xbox('Xbox Series'),
  pc('PC');

  const GamePlatform(this.label);
  final String label;
}

/// Posizioni in campo disponibili nel menu di modifica.
const fieldPositions = [
  'POR',
  'DC',
  'TD',
  'TS',
  'CDC',
  'CC',
  'COC',
  'ED',
  'ES',
  'AD',
  'AS',
  'ATT',
];
