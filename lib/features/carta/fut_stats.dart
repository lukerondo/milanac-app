/// Una delle sei statistiche FUT della carta. Le chiavi sono quelle salvate in
/// `profiles.fut_stats` (migrazione 0032); le sigle sono quelle del gioco in italiano.
enum FutStat {
  velocita('pac', 'VEL', 'Velocità'),
  tiro('sho', 'TIR', 'Tiro'),
  passaggio('pas', 'PAS', 'Passaggio'),
  dribbling('dri', 'DRI', 'Dribbling'),
  difesa('def', 'DIF', 'Difesa'),
  fisico('phy', 'FIS', 'Fisico'),
  tuffo('div', 'TUF', 'Tuffo'),
  presa('han', 'PRE', 'Presa'),
  rinvio('kic', 'RIN', 'Rinvio'),
  riflessi('ref', 'RIF', 'Riflessi'),
  velocitaPortiere('spd', 'VEL', 'Velocità'),
  piazzamento('pos', 'PIA', 'Piazzamento');

  const FutStat(this.key, this.short, this.label);
  final String key;

  /// Sigla sulla carta (VEL, TIR...).
  final String short;
  final String label;

  static const outfield = [
    velocita,
    tiro,
    passaggio,
    dribbling,
    difesa,
    fisico,
  ];
  static const keeper = [
    tuffo,
    presa,
    rinvio,
    riflessi,
    velocitaPortiere,
    piazzamento,
  ];

  /// Le sei statistiche mostrate per un ruolo: quelle da portiere per il POR.
  static List<FutStat> forPosition(String? position) =>
      position == 'POR' ? keeper : outfield;

  static final _byKey = {for (final s in values) s.key: s};
}

/// Le statistiche FUT di un giocatore (da 1 a 99), le inserisce lui o il Direttivo.
/// Quelle da portiere e quelle di movimento restano separate: cambiando ruolo non si
/// perde niente.
class FutStats {
  const FutStats([this._values = const {}]);

  static const empty = FutStats();
  static const min = 1, max = 99;

  final Map<FutStat, int> _values;

  int? operator [](FutStat stat) => _values[stat];

  bool get isEmpty => _values.isEmpty;

  /// Ha almeno una statistica tra quelle del ruolo.
  bool hasAnyFor(String? position) =>
      FutStat.forPosition(position).any(_values.containsKey);

  /// Copia con [stat] impostata a [value] (null la toglie).
  FutStats withValue(FutStat stat, int? value) {
    final next = {..._values};
    if (value == null) {
      next.remove(stat);
    } else {
      next[stat] = value.clamp(min, max);
    }
    return FutStats(next);
  }

  /// Letto senza fidarsi: chiavi sconosciute e valori fuori da 1–99 si saltano.
  static FutStats fromJson(Object? json) {
    if (json is! Map) return empty;
    final values = <FutStat, int>{};
    json.forEach((k, v) {
      final stat = FutStat._byKey[k];
      if (stat != null && v is num && v == v.roundToDouble()) {
        final n = v.toInt();
        if (n >= min && n <= max) values[stat] = n;
      }
    });
    return values.isEmpty ? empty : FutStats(values);
  }

  Map<String, int> toJson() => {
    for (final e in _values.entries) e.key.key: e.value,
  };

  @override
  bool operator ==(Object other) =>
      other is FutStats &&
      other._values.length == _values.length &&
      _values.entries.every((e) => other._values[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
