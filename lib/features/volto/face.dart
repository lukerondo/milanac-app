import 'dart:math';

/// Il volto del giocatore: pochi numeri, uno per ogni parte, disegnati dall'app.
/// Si salva nel profilo come JSON (colonna `face`).
class Face {
  const Face({
    this.skin = 2,
    this.hair = 1,
    this.hairColor = 1,
    this.eyes = 0,
    this.eyeColor = 0,
    this.brows = 0,
    this.beard = 0,
    this.mouth = 0,
    this.accessory = 0,
  });

  /// Tonalità della pelle (0-5).
  final int skin;

  /// Taglio di capelli (0 = rasato ... vedi [FacePart.hair]).
  final int hair;
  final int hairColor;
  final int eyes;
  final int eyeColor;
  final int brows;
  final int beard;
  final int mouth;
  final int accessory;

  static const defaults = Face();

  Map<String, dynamic> toJson() => {
    'skin': skin,
    'hair': hair,
    'hairColor': hairColor,
    'eyes': eyes,
    'eyeColor': eyeColor,
    'brows': brows,
    'beard': beard,
    'mouth': mouth,
    'accessory': accessory,
  };

  static Face? fromJson(Object? json) {
    if (json is! Map) return null;
    int read(String key, FacePart part, int fallback) {
      final v = json[key];
      final n = v is num ? v.toInt() : fallback;
      return n.clamp(0, part.count - 1);
    }

    return Face(
      skin: read('skin', FacePart.skin, 2),
      hair: read('hair', FacePart.hair, 1),
      hairColor: read('hairColor', FacePart.hairColor, 1),
      eyes: read('eyes', FacePart.eyes, 0),
      eyeColor: read('eyeColor', FacePart.eyeColor, 0),
      brows: read('brows', FacePart.brows, 0),
      beard: read('beard', FacePart.beard, 0),
      mouth: read('mouth', FacePart.mouth, 0),
      accessory: read('accessory', FacePart.accessory, 0),
    );
  }

  int valueOf(FacePart part) => switch (part) {
    FacePart.skin => skin,
    FacePart.hair => hair,
    FacePart.hairColor => hairColor,
    FacePart.eyes => eyes,
    FacePart.eyeColor => eyeColor,
    FacePart.brows => brows,
    FacePart.beard => beard,
    FacePart.mouth => mouth,
    FacePart.accessory => accessory,
  };

  Face withPart(FacePart part, int value) {
    final v = value.clamp(0, part.count - 1);
    return Face(
      skin: part == FacePart.skin ? v : skin,
      hair: part == FacePart.hair ? v : hair,
      hairColor: part == FacePart.hairColor ? v : hairColor,
      eyes: part == FacePart.eyes ? v : eyes,
      eyeColor: part == FacePart.eyeColor ? v : eyeColor,
      brows: part == FacePart.brows ? v : brows,
      beard: part == FacePart.beard ? v : beard,
      mouth: part == FacePart.mouth ? v : mouth,
      accessory: part == FacePart.accessory ? v : accessory,
    );
  }

  /// Un volto a caso (pulsante "A caso" nell'editor).
  static Face random([Random? rnd]) {
    final r = rnd ?? Random();
    return Face(
      skin: r.nextInt(FacePart.skin.count),
      hair: r.nextInt(FacePart.hair.count),
      hairColor: r.nextInt(FacePart.hairColor.count),
      eyes: r.nextInt(FacePart.eyes.count),
      eyeColor: r.nextInt(FacePart.eyeColor.count),
      brows: r.nextInt(FacePart.brows.count),
      beard: r.nextInt(FacePart.beard.count),
      mouth: r.nextInt(FacePart.mouth.count),
      accessory: r.nextInt(FacePart.accessory.count),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Face &&
      other.skin == skin &&
      other.hair == hair &&
      other.hairColor == hairColor &&
      other.eyes == eyes &&
      other.eyeColor == eyeColor &&
      other.brows == brows &&
      other.beard == beard &&
      other.mouth == mouth &&
      other.accessory == accessory;

  @override
  int get hashCode => Object.hash(
    skin,
    hair,
    hairColor,
    eyes,
    eyeColor,
    brows,
    beard,
    mouth,
    accessory,
  );
}

/// Le parti del volto che si scelgono nell'editor, con le opzioni disponibili.
enum FacePart {
  skin('Pelle', ['Chiara', 'Rosata', 'Olivastra', 'Ambrata', 'Bruna', 'Scura']),
  hair('Capelli', [
    'Rasati',
    'Corti',
    'Ciuffo',
    'Riga laterale',
    'Ricci',
    'Lunghi',
    'Cresta',
    'Chignon',
    'Calvo',
  ]),
  hairColor('Colore capelli', [
    'Neri',
    'Castani',
    'Biondi',
    'Rossi',
    'Grigi',
    'Platino',
  ]),
  eyes('Occhi', ['Normali', 'Allungati', 'Grandi', 'Socchiusi']),
  eyeColor('Colore occhi', ['Marroni', 'Azzurri', 'Verdi', 'Nocciola']),
  brows('Sopracciglia', ['Normali', 'Folte', 'Decise']),
  beard('Barba', ['Nessuna', 'Incolta', 'Corta', 'Piena', 'Pizzetto', 'Baffi']),
  mouth('Bocca', ['Sorriso', 'Seria', 'Grinta']),
  accessory('Accessori', [
    'Nessuno',
    'Fascia',
    'Occhiali',
    'Orecchino',
    'Cerotto',
  ]);

  const FacePart(this.label, this.options);
  final String label;
  final List<String> options;
  int get count => options.length;
}
