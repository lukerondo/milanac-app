import '../teams.dart';

enum ClubRole { direttivo, giocatore, pending }

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
  });

  final String id;
  final String displayName;
  final ClubRole role;

  /// Ruolo scelto dall'utente al primo accesso (lo conferma il Direttivo).
  final ClubRole requestedRole;

  /// false se il Direttivo ha rifiutato la richiesta o rimosso il membro.
  final bool active;
  final String? gamertag;
  final String? avatarUrl;

  /// Squadre in cui gioca (MILANAC, MILANAC FUTURO o entrambe).
  final Set<Team> teams;

  bool get isDirettivo => role == ClubRole.direttivo && active;
  bool get isApproved => role != ClubRole.pending && active;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id: m['id'] as String,
    displayName: (m['display_name'] as String?) ?? 'Giocatore',
    gamertag: m['gamertag'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    active: (m['active'] as bool?) ?? true,
    role: parseRole(m['club_role'], ClubRole.pending),
    requestedRole: parseRole(m['requested_role'], ClubRole.giocatore),
    teams: Team.parseSet(m['teams']),
  );

  static const demo = Profile(
    id: 'demo',
    displayName: 'Demo Direttivo',
    gamertag: 'MILANAC_Demo',
    role: ClubRole.direttivo,
  );
}

ClubRole parseRole(Object? value, ClubRole fallback) =>
    ClubRole.values.asNameMap()[value] ?? fallback;
