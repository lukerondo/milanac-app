import '../../core/auth/profile.dart';

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
    role: ClubRole.values.firstWhere(
      (r) => r.name == m['club_role'],
      orElse: () => ClubRole.pending,
    ),
  );

  /// Campi modificabili dal Direttivo.
  Map<String, dynamic> toUpdateMap() => {
    'display_name': displayName,
    'gamertag': gamertag,
    'club_role': role.name,
    'field_position': fieldPosition,
    'shirt_number': shirtNumber,
    'joined_at': joinedAt.toIso8601String().substring(0, 10),
    'active': active,
  };
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
