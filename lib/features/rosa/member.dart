import '../../core/auth/profile.dart';
import '../../core/teams.dart';
import '../volto/face.dart';

/// Valore predefinito dei campi svuotabili di [Member.copyWith]: "non toccare".
class _Same {
  const _Same();
}

const _same = _Same();

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
    this.firstName,
    this.lastName,
    this.birthYear,
    this.motto,
    this.direttivoRoles = const [],
    this.face,
    this.registrationCompleted = true,
  });

  final String id;

  /// Nome sulla carta: è il nome con cui il membro compare in tutta l'app.
  final String displayName;
  final ClubRole role;
  final DateTime joinedAt;
  final String? gamertag;
  final String? fieldPosition;
  final int? shirtNumber;
  final String? avatarUrl;
  final bool active;

  /// Ruolo chiesto alla registrazione (Direttivo solo con la password del club).
  final ClubRole requestedRole;

  /// Squadre in cui gioca: le sceglie alla registrazione, le cambia il Direttivo.
  final Set<Team> teams;

  /// Carta FUT: overall (40–99) deciso dal Direttivo, stile di gioco e piattaforma.
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

  /// Dati della registrazione: nome, cognome e anno di nascita (con la data di nascita
  /// sono i dati anagrafici di `profile_private`: arrivano solo quelli propri, al
  /// Direttivo quelli di tutti), motto, etichette del Direttivo e volto disegnato.
  final String? firstName;
  final String? lastName;
  final int? birthYear;
  final String? motto;
  final List<DirettivoRole> direttivoRoles;
  final Face? face;
  final bool registrationCompleted;

  int? get age {
    final b = birthDate;
    if (b != null) {
      final now = DateTime.now();
      final hadBirthday =
          now.month > b.month || (now.month == b.month && now.day >= b.day);
      return now.year - b.year - (hadBirthday ? 0 : 1);
    }
    final y = birthYear;
    return y == null ? null : DateTime.now().year - y;
  }

  /// Nome e cognome (per il Direttivo e per sé), altrimenti il nome sulla carta.
  String get fullName {
    final parts = [
      firstName,
      lastName,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? displayName : parts.join(' ');
  }

  bool inTeam(Team? team) => team == null || teams.contains(team);

  String get roleLabel => switch (role) {
    ClubRole.direttivo => 'Direttivo',
    ClubRole.giocatore => 'Giocatore',
    ClubRole.pending => 'Registrazione in corso',
  };

  /// Etichette del Direttivo ("Capitano, Gestore"), vuoto per i giocatori.
  String get direttivoLabel => direttivoRoles.map((r) => r.label).join(', ');

  /// Copia con i campi indicati. Gamertag, posizione, numero di maglia, stile,
  /// piattaforma e dati anagrafici si possono svuotare passando null (omessi restano
  /// come sono); per gli altri campi null vuol dire "invariato".
  Member copyWith({
    String? displayName,
    ClubRole? role,
    DateTime? joinedAt,
    Object? gamertag = _same,
    Object? fieldPosition = _same,
    Object? shirtNumber = _same,
    bool? active,
    Set<Team>? teams,
    int? overall,
    Object? playStyle = _same,
    Object? platform = _same,
    Face? face,
    String? motto,
    Object? firstName = _same,
    Object? lastName = _same,
    Object? birthYear = _same,
    Object? birthDate = _same,
  }) => Member(
    id: id,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    joinedAt: joinedAt ?? this.joinedAt,
    gamertag: identical(gamertag, _same) ? this.gamertag : gamertag as String?,
    fieldPosition: identical(fieldPosition, _same)
        ? this.fieldPosition
        : fieldPosition as String?,
    shirtNumber: identical(shirtNumber, _same)
        ? this.shirtNumber
        : shirtNumber as int?,
    avatarUrl: avatarUrl,
    active: active ?? this.active,
    requestedRole: requestedRole,
    teams: teams ?? this.teams,
    overall: overall ?? this.overall,
    playStyle: identical(playStyle, _same)
        ? this.playStyle
        : playStyle as String?,
    platform: identical(platform, _same)
        ? this.platform
        : platform as GamePlatform?,
    avatarPath: avatarPath,
    birthDate: identical(birthDate, _same)
        ? this.birthDate
        : birthDate as DateTime?,
    city: city,
    nationality: nationality,
    preferredFoot: preferredFoot,
    firstName: identical(firstName, _same)
        ? this.firstName
        : firstName as String?,
    lastName: identical(lastName, _same) ? this.lastName : lastName as String?,
    birthYear: identical(birthYear, _same) ? this.birthYear : birthYear as int?,
    motto: motto ?? this.motto,
    direttivoRoles: direttivoRoles,
    face: face ?? this.face,
    registrationCompleted: registrationCompleted,
  );

  /// Lo stesso membro senza dati anagrafici: come lo riceve chi non è del Direttivo.
  Member withoutPrivateData() => copyWith(
    firstName: null,
    lastName: null,
    birthYear: null,
    birthDate: null,
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
    firstName: m['first_name'] as String?,
    lastName: m['last_name'] as String?,
    birthYear: (m['birth_year'] as num?)?.toInt(),
    motto: m['motto'] as String?,
    direttivoRoles: DirettivoRole.parseList(m['direttivo_roles']),
    face: Face.fromJson(m['face']),
    registrationCompleted: m['registration_completed_at'] != null,
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
    String? firstName,
    String? lastName,
    int? birthYear,
    String? motto,
    Face? face,
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
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    birthYear: birthYear ?? this.birthYear,
    motto: motto ?? this.motto,
    direttivoRoles: direttivoRoles,
    face: face ?? this.face,
    registrationCompleted: registrationCompleted,
  );

  /// Campi personali di `profiles`, modificabili dal membro sul proprio profilo (i dati
  /// anagrafici sono a parte: [privateMap]).
  Map<String, dynamic> personalMap() => {
    'display_name': displayName,
    'gamertag': gamertag,
    'city': city,
    'nationality': nationality,
    'preferred_foot': preferredFoot?.name,
    'motto': motto,
    'face': face?.toJson(),
  };

  /// Dati anagrafici da salvare (`profile_private`): solo quelli presenti. Dalle
  /// Impostazioni non si cancellano, e così chi non li ha ricevuti non li azzera.
  Map<String, dynamic> privateMap() => {
    'first_name': ?firstName,
    'last_name': ?lastName,
    'birth_year': ?birthYear,
    'birth_date': ?birthDate?.toIso8601String().substring(0, 10),
  };

  /// Campi modificabili dal Direttivo (mai i dati anagrafici: dopo la migrazione 0025
  /// non sono più colonne di `profiles`).
  Map<String, dynamic> toUpdateMap() => {
    'display_name': displayName,
    'gamertag': gamertag,
    'club_role': role.name,
    'joined_at': joinedAt.toIso8601String().substring(0, 10),
    'active': active,
    'teams': teamsToJson(teams),
    'overall': overall,
    ...cardMap(),
  };

  /// Campi della carta modificabili anche dal giocatore (l'overall no: lo decide il Direttivo).
  Map<String, dynamic> cardMap() => {
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

/// Reparto di una posizione (per le carte speciali: un premiato per reparto).
String repartoOf(String? position) => switch (position) {
  'POR' => 'POR',
  'DC' || 'TD' || 'TS' => 'DIF',
  'CDC' || 'CC' || 'COC' => 'CEN',
  'ED' || 'ES' || 'AD' || 'AS' || 'ATT' => 'ATT',
  _ => '–',
};
