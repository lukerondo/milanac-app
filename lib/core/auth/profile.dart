import '../../features/volto/face.dart';
import '../teams.dart';

enum ClubRole { direttivo, giocatore, pending }

/// Etichette di chi fa parte del Direttivo (anche più d'una, senza poteri diversi).
enum DirettivoRole {
  capitano('Capitano'),
  reclutatore('Reclutatore'),
  organizzatore('Organizzatore'),
  gestore('Gestore');

  const DirettivoRole(this.label);
  final String label;

  static List<DirettivoRole> parseList(Object? value) => [
    if (value is List)
      for (final v in value) ?DirettivoRole.values.asNameMap()[v],
  ];
}

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.role,
    this.requestedRole = ClubRole.giocatore,
    this.active = true,
    this.gamertag,
    this.avatarUrl,
    this.teams = const {Team.milanac},
    this.firstName,
    this.lastName,
    this.birthYear,
    this.motto,
    this.direttivoRoles = const [],
    this.face,
    this.platform,
    this.fieldPosition,
    this.shirtNumber,
    this.overall,
    this.registrationCompleted = false,
    this.rulesAcceptedVersion,
  });

  final String id;

  /// Nome sulla carta: è il nome con cui il membro compare in tutta l'app.
  final String displayName;
  final ClubRole role;

  /// Ruolo chiesto alla registrazione (Direttivo solo con la password del club);
  /// diventa il ruolo vero quando si accetta il regolamento.
  final ClubRole requestedRole;

  /// false se il Direttivo ha bloccato o rimosso il membro.
  final bool active;
  final String? gamertag;
  final String? avatarUrl;

  /// Squadre in cui gioca (Milan AC, Milan AC Futuro o entrambe).
  final Set<Team> teams;

  final String? firstName;
  final String? lastName;
  final int? birthYear;
  final String? motto;
  final List<DirettivoRole> direttivoRoles;
  final Face? face;
  final String? platform;
  final String? fieldPosition;
  final int? shirtNumber;
  final int? overall;

  /// true quando i tre passi della registrazione sono stati completati.
  final bool registrationCompleted;

  /// Ultima versione del regolamento accettata (null = mai).
  final int? rulesAcceptedVersion;

  bool get isDirettivo => role == ClubRole.direttivo && active;
  bool get isApproved => role != ClubRole.pending && active;

  /// Nome e cognome (visibili al Direttivo), altrimenti il nome sulla carta.
  String get fullName {
    final parts = [
      firstName,
      lastName,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? displayName : parts.join(' ');
  }

  /// Etichetta del ruolo nel club, con le etichette del Direttivo.
  String get roleLabel {
    if (role == ClubRole.direttivo) {
      final tags = direttivoRoles.map((r) => r.label).join(', ');
      return tags.isEmpty ? 'Direttivo' : 'Direttivo · $tags';
    }
    return role == ClubRole.giocatore ? 'Giocatore' : 'Registrazione in corso';
  }

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id: m['id'] as String,
    displayName: (m['display_name'] as String?) ?? 'Giocatore',
    gamertag: m['gamertag'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    active: (m['active'] as bool?) ?? true,
    role: parseRole(m['club_role'], ClubRole.pending),
    requestedRole: parseRole(m['requested_role'], ClubRole.giocatore),
    teams: Team.parseSet(m['teams']),
    firstName: m['first_name'] as String?,
    lastName: m['last_name'] as String?,
    birthYear: (m['birth_year'] as num?)?.toInt(),
    motto: m['motto'] as String?,
    direttivoRoles: DirettivoRole.parseList(m['direttivo_roles']),
    face: Face.fromJson(m['face']),
    platform: m['platform'] as String?,
    fieldPosition: m['field_position'] as String?,
    shirtNumber: (m['shirt_number'] as num?)?.toInt(),
    overall: (m['overall'] as num?)?.toInt(),
    registrationCompleted: m['registration_completed_at'] != null,
    rulesAcceptedVersion: (m['rules_accepted_version'] as num?)?.toInt(),
  );

  static const demo = Profile(
    id: 'demo',
    displayName: 'Demo Direttivo',
    firstName: 'Demo',
    lastName: 'Direttivo',
    gamertag: 'MILANAC_Demo',
    role: ClubRole.direttivo,
    direttivoRoles: [DirettivoRole.capitano, DirettivoRole.gestore],
    platform: 'ps5',
    face: Face.defaults,
    registrationCompleted: true,
    rulesAcceptedVersion: 1,
  );
}

ClubRole parseRole(Object? value, ClubRole fallback) =>
    ClubRole.values.asNameMap()[value] ?? fallback;
