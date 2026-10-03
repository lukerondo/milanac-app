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
    this.avatarPath,
    this.birthDate,
    this.city,
    this.nationality,
    this.preferredFoot,
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

  /// Dati del profilo (Impostazioni): foto caricata, nascita, città, nazionalità, piede.
  final String? avatarPath;
  final DateTime? birthDate;
  final String? city;

  /// Codice ISO a 2 lettere (IT, ES...).
  final String? nationality;
  final PreferredFoot? preferredFoot;

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    final hadBirthday =
        now.month > b.month || (now.month == b.month && now.day >= b.day);
    return now.year - b.year - (hadBirthday ? 0 : 1);
  }

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
    avatarPath: avatarPath,
    birthDate: birthDate,
    city: city,
    nationality: nationality,
    preferredFoot: preferredFoot,
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
    avatarPath: m['avatar_path'] as String?,
    birthDate: m['birth_date'] == null
        ? null
        : DateTime.parse(m['birth_date'] as String),
    city: m['city'] as String?,
    nationality: m['nationality'] as String?,
    preferredFoot: PreferredFoot.values.asNameMap()[m['preferred_foot']],
  );

  /// Copia con i dati personali modificati dalle Impostazioni (null = svuota).
  Member withPersonalData({
    required String displayName,
    required String? gamertag,
    required DateTime? birthDate,
    required String? city,
    required String? nationality,
    required PreferredFoot? preferredFoot,
    String? avatarPath,
  }) => Member(
    id: id,
    displayName: displayName,
    role: role,
    joinedAt: joinedAt,
    gamertag: gamertag,
    fieldPosition: fieldPosition,
    shirtNumber: shirtNumber,
    avatarUrl: avatarUrl,
    active: active,
    requestedRole: requestedRole,
    teams: teams,
    overall: overall,
    playStyle: playStyle,
    platform: platform,
    avatarPath: avatarPath ?? this.avatarPath,
    birthDate: birthDate,
    city: city,
    nationality: nationality,
    preferredFoot: preferredFoot,
  );

  /// Campi personali, modificabili dal membro sul proprio profilo.
  Map<String, dynamic> personalMap() => {
    'display_name': displayName,
    'gamertag': gamertag,
    'birth_date': birthDate?.toIso8601String().substring(0, 10),
    'city': city,
    'nationality': nationality,
    'preferred_foot': preferredFoot?.name,
  };

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

enum PreferredFoot {
  destro('Destro'),
  sinistro('Sinistro'),
  ambidestro('Ambidestro');

  const PreferredFoot(this.label);
  final String label;
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
