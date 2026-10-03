enum ClubRole { direttivo, giocatore, pending }

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.role,
    this.gamertag,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final ClubRole role;
  final String? gamertag;
  final String? avatarUrl;

  bool get isDirettivo => role == ClubRole.direttivo;
  bool get isApproved => role != ClubRole.pending;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        displayName: (m['display_name'] as String?) ?? 'Giocatore',
        gamertag: m['gamertag'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        role: ClubRole.values.firstWhere(
          (r) => r.name == m['club_role'],
          orElse: () => ClubRole.pending,
        ),
      );

  static const demo = Profile(
    id: 'demo',
    displayName: 'Demo Direttivo',
    gamertag: 'MILANAC_Demo',
    role: ClubRole.direttivo,
  );
}
