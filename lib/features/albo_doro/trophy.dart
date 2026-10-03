import 'dart:typed_data';

/// Forma disegnata dall'app quando il Direttivo non carica un'immagine del trofeo.
enum TrophyShape {
  coppa('Coppa'),
  targa('Targa'),
  medaglia('Medaglia'),
  scudetto('Scudetto'),
  stella('Stella');

  const TrophyShape(this.label);
  final String label;
}

class Season {
  const Season({required this.id, required this.label});
  final String id;

  /// es. "2025/26".
  final String label;

  factory Season.fromMap(Map<String, dynamic> m) =>
      Season(id: m['id'] as String, label: m['label'] as String);
}

/// Etichetta della stagione calcistica in corso (da luglio a giugno).
String currentSeasonLabel([DateTime? now]) {
  final d = now ?? DateTime.now();
  final start = d.month >= 7 ? d.year : d.year - 1;
  return '$start/${((start + 1) % 100).toString().padLeft(2, '0')}';
}

class Trophy {
  const Trophy({
    required this.id,
    required this.seasonId,
    required this.name,
    this.competition,
    this.wonOn,
    this.shape = TrophyShape.coppa,
    this.imagePath,
    this.description,
    this.localBytes,
  });

  final String id;
  final String seasonId;
  final String name;
  final String? competition;
  final DateTime? wonOn;
  final TrophyShape shape;
  final String? imagePath;
  final String? description;

  /// Solo modalità demo: immagine in memoria.
  final Uint8List? localBytes;

  bool get hasImage => imagePath != null || localBytes != null;

  factory Trophy.fromMap(Map<String, dynamic> m) => Trophy(
    id: m['id'] as String,
    seasonId: m['season_id'] as String,
    name: m['name'] as String,
    competition: m['competition'] as String?,
    wonOn: m['won_on'] == null ? null : DateTime.parse(m['won_on'] as String),
    shape: TrophyShape.values.asNameMap()[m['shape']] ?? TrophyShape.coppa,
    imagePath: m['image_path'] as String?,
    description: m['description'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'season_id': seasonId,
    'name': name,
    'competition': competition,
    'won_on': wonOn?.toIso8601String().substring(0, 10),
    'shape': shape.name,
    'image_path': imagePath,
    'description': description,
  };

  @override
  bool operator ==(Object other) =>
      other is Trophy && other.id == id && other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(id, imagePath);
}
