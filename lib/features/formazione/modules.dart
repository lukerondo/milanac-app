import '../../core/italian_time.dart';
import '../../core/teams.dart';

/// Una posizione in campo: [x] da 0 (sinistra) a 1 (destra),
/// [y] da 0 (porta avversaria, in alto) a 1 (nostra porta, in basso).
class SlotPosition {
  const SlotPosition(this.label, this.x, this.y);
  final String label;
  final double x;
  final double y;
}

/// Moduli disponibili. L'indice 0 è sempre il portiere.
const formationModules = <String, List<SlotPosition>>{
  '4-3-3': [
    SlotPosition('POR', .5, .92),
    SlotPosition('TS', .12, .72),
    SlotPosition('DC', .37, .76),
    SlotPosition('DC', .63, .76),
    SlotPosition('TD', .88, .72),
    SlotPosition('CC', .25, .5),
    SlotPosition('CDC', .5, .56),
    SlotPosition('CC', .75, .5),
    SlotPosition('AS', .18, .24),
    SlotPosition('ATT', .5, .17),
    SlotPosition('AD', .82, .24),
  ],
  '4-2-3-1': [
    SlotPosition('POR', .5, .92),
    SlotPosition('TS', .12, .72),
    SlotPosition('DC', .37, .76),
    SlotPosition('DC', .63, .76),
    SlotPosition('TD', .88, .72),
    SlotPosition('CDC', .35, .56),
    SlotPosition('CDC', .65, .56),
    SlotPosition('ES', .16, .35),
    SlotPosition('COC', .5, .37),
    SlotPosition('ED', .84, .35),
    SlotPosition('ATT', .5, .16),
  ],
  '4-4-2': [
    SlotPosition('POR', .5, .92),
    SlotPosition('TS', .12, .72),
    SlotPosition('DC', .37, .76),
    SlotPosition('DC', .63, .76),
    SlotPosition('TD', .88, .72),
    SlotPosition('ES', .12, .46),
    SlotPosition('CC', .37, .5),
    SlotPosition('CC', .63, .5),
    SlotPosition('ED', .88, .46),
    SlotPosition('ATT', .35, .2),
    SlotPosition('ATT', .65, .2),
  ],
  '4-1-2-1-2': [
    SlotPosition('POR', .5, .92),
    SlotPosition('TS', .12, .72),
    SlotPosition('DC', .37, .76),
    SlotPosition('DC', .63, .76),
    SlotPosition('TD', .88, .72),
    SlotPosition('CDC', .5, .6),
    SlotPosition('CC', .25, .48),
    SlotPosition('CC', .75, .48),
    SlotPosition('COC', .5, .35),
    SlotPosition('ATT', .35, .18),
    SlotPosition('ATT', .65, .18),
  ],
  '3-5-2': [
    SlotPosition('POR', .5, .92),
    SlotPosition('DC', .25, .75),
    SlotPosition('DC', .5, .78),
    SlotPosition('DC', .75, .75),
    SlotPosition('ES', .1, .45),
    SlotPosition('CDC', .35, .55),
    SlotPosition('CDC', .65, .55),
    SlotPosition('ED', .9, .45),
    SlotPosition('COC', .5, .38),
    SlotPosition('ATT', .35, .18),
    SlotPosition('ATT', .65, .18),
  ],
  '3-4-3': [
    SlotPosition('POR', .5, .92),
    SlotPosition('DC', .25, .75),
    SlotPosition('DC', .5, .78),
    SlotPosition('DC', .75, .75),
    SlotPosition('ES', .12, .48),
    SlotPosition('CC', .37, .52),
    SlotPosition('CC', .63, .52),
    SlotPosition('ED', .88, .48),
    SlotPosition('AS', .18, .24),
    SlotPosition('ATT', .5, .17),
    SlotPosition('AD', .82, .24),
  ],
  '5-3-2': [
    SlotPosition('POR', .5, .92),
    SlotPosition('ES', .08, .62),
    SlotPosition('DC', .28, .76),
    SlotPosition('DC', .5, .79),
    SlotPosition('DC', .72, .76),
    SlotPosition('ED', .92, .62),
    SlotPosition('CC', .25, .46),
    SlotPosition('CDC', .5, .52),
    SlotPosition('CC', .75, .46),
    SlotPosition('ATT', .35, .2),
    SlotPosition('ATT', .65, .2),
  ],
};

const defaultModule = '4-3-3';

/// Le palle inattive: chi le batte lo decide in anticipo lo staff tecnico (regolamento).
/// [key] è la chiave in `formations.set_pieces`, [label] il nome nell'app e nel PDF,
/// [short] quello della riga in Comunicazioni.
enum SetPiece {
  rigori('rigori', 'Rigori', 'rigori'),
  punizioni('punizioni', 'Punizioni', 'punizioni'),
  angoliSinistra('angoli_sx', 'Angoli da sinistra', 'angoli sx'),
  angoliDestra('angoli_dx', 'Angoli da destra', 'angoli dx');

  const SetPiece(this.key, this.label, this.short);
  final String key;
  final String label;
  final String short;

  static SetPiece? parse(String? key) =>
      values.where((r) => r.key == key).firstOrNull;
}

/// I battitori come li salva il database (`{"rigori": id, "angoli_sx": id, ...}`).
Map<String, String> setPiecesJson(Map<SetPiece, String> takers) => {
  for (final e in takers.entries) e.key.key: e.value,
};

/// I battitori letti dal database: le chiavi che l'app non conosce si ignorano.
Map<SetPiece, String> parseSetPieces(Object? json) => switch (json) {
  final Map<String, dynamic> m => {
    for (final e in m.entries)
      if ((SetPiece.parse(e.key), e.value) case (final role?, final String id))
        role: id,
  },
  _ => const {},
};

/// I battitori tra i soli [players] (i titolari): i ruoli di chi non è in campo restano
/// liberi.
Map<SetPiece, String> setPiecesAmong(
  Map<SetPiece, String> takers,
  Iterable<String> players,
) {
  final onField = players.toSet();
  return {
    for (final e in takers.entries)
      if (onField.contains(e.value)) e.key: e.value,
  };
}

/// "Palle inattive: rigori Rossi · punizioni Bianchi · angoli sx Verdi, dx Neri", o null
/// senza battitori: nel testo che accompagna il PDF condiviso, ed è la riga che il
/// database aggiunge all'annuncio in Comunicazioni (`set_pieces_line`, stesse regole).
/// [nameOf] dà il nome di un giocatore (null = non più nel club: il suo ruolo non si
/// scrive).
String? setPiecesLine(
  Map<SetPiece, String> takers,
  String? Function(String id) nameOf,
) {
  String? name(SetPiece role) => switch (takers[role]) {
    final id? => nameOf(id),
    null => null,
  };
  final sx = name(SetPiece.angoliSinistra), dx = name(SetPiece.angoliDestra);
  final parts = [
    for (final role in [SetPiece.rigori, SetPiece.punizioni])
      if (name(role) case final n?) '${role.short} $n',
    if (sx != null && dx != null)
      takers[SetPiece.angoliSinistra] == takers[SetPiece.angoliDestra]
          ? 'angoli $sx'
          : 'angoli sx $sx, dx $dx'
    else if (sx != null)
      'angoli sx $sx'
    else if (dx != null)
      'angoli dx $dx',
  ];
  return parts.isEmpty ? null : 'Palle inattive: ${parts.join(' · ')}';
}

/// Formazione corrente: modulo + giocatore assegnato a ciascuna delle 11 posizioni.
class Formation {
  const Formation({
    this.id = '',
    this.team = Team.milanac,
    this.module = defaultModule,
    this.players = const {},
    this.setPieces = const {},
    this.publishedAt,
    this.updatedAt,
    this.publishedModule,
    this.publishedPlayers,
    this.publishedSetPieces,
  });

  final String id;

  /// Squadra a cui appartiene (una formazione per squadra).
  final Team team;
  final String module;

  /// Quando il Direttivo l'ha pubblicata (null = ancora bozza).
  final DateTime? publishedAt;
  final DateTime? updatedAt;

  /// Modulo e giocatori "congelati" all'ultima pubblicazione (quello che vedono i giocatori).
  final String? publishedModule;
  final Map<int, String>? publishedPlayers;

  /// I battitori dell'ultima pubblicazione (null = mai pubblicata, o pubblicata prima
  /// dei battitori).
  final Map<SetPiece, String>? publishedSetPieces;

  /// La formazione come l'hanno ricevuta i giocatori (vuota se mai pubblicata).
  Formation get publishedView => Formation(
    id: id,
    team: team,
    module: publishedModule ?? module,
    players: publishedPlayers ?? const {},
    setPieces: publishedSetPieces ?? const {},
    publishedAt: publishedAt,
    updatedAt: publishedAt,
    publishedModule: publishedModule,
    publishedPlayers: publishedPlayers,
    publishedSetPieces: publishedSetPieces,
  );

  bool get isPublished => publishedAt != null;

  /// Pubblicata nel giorno italiano [day] (vale come formazione "di stasera").
  bool isPublishedOn(DateTime day) {
    final p = publishedAt == null ? null : italianClock(publishedAt!);
    return p != null &&
        p.year == day.year &&
        p.month == day.month &&
        p.day == day.day;
  }

  /// Modificata dopo l'ultima pubblicazione: modulo, giocatori o battitori diversi da
  /// quelli che hanno ricevuto i giocatori. Si confronta il contenuto, non gli orari (il
  /// salvataggio usa l'ora del server, la pubblicazione quella del telefono).
  bool get hasUnpublishedChanges {
    if (publishedAt == null) return false;
    bool differ<K>(Map<K, String> a, Map<K, String> b) =>
        a.length != b.length || a.entries.any((e) => b[e.key] != e.value);
    return (publishedModule ?? module) != module ||
        differ(players, publishedPlayers ?? const {}) ||
        differ(setPieces, publishedSetPieces ?? const {});
  }

  /// Posizione (es. "CC") del giocatore, o null se in panchina.
  String? positionOf(String playerId) {
    for (final e in players.entries) {
      if (e.value == playerId) return slots[e.key].label;
    }
    return null;
  }

  /// slot (0–10) → id del giocatore.
  final Map<int, String> players;

  /// Chi batte le palle inattive: un titolare per ruolo (lo stesso può averne più d'uno),
  /// ogni ruolo facoltativo.
  final Map<SetPiece, String> setPieces;

  /// I ruoli sulle palle inattive di [playerId], nell'ordine di [SetPiece].
  List<SetPiece> setPiecesOf(String playerId) => [
    for (final role in SetPiece.values)
      if (setPieces[role] == playerId) role,
  ];

  List<SlotPosition> get slots =>
      formationModules[module] ?? formationModules[defaultModule]!;

  Formation copyWith({
    String? id,
    Team? team,
    String? module,
    Map<int, String>? players,
    Map<SetPiece, String>? setPieces,
    DateTime? publishedAt,
    DateTime? updatedAt,
    String? publishedModule,
    Map<int, String>? publishedPlayers,
    Map<SetPiece, String>? publishedSetPieces,
  }) => Formation(
    id: id ?? this.id,
    team: team ?? this.team,
    module: module ?? this.module,
    players: players ?? this.players,
    setPieces: setPieces ?? this.setPieces,
    publishedAt: publishedAt ?? this.publishedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    publishedModule: publishedModule ?? this.publishedModule,
    publishedPlayers: publishedPlayers ?? this.publishedPlayers,
    publishedSetPieces: publishedSetPieces ?? this.publishedSetPieces,
  );

  /// Mette [playerId] nello [slot]; se era già in campo altrove, lo sposta. Chi esce dal
  /// campo perde i suoi ruoli sulle palle inattive (restano da scegliere): un battitore
  /// è sempre un titolare.
  Formation assign(int slot, String? playerId) {
    final next = Map.of(players)..removeWhere((_, p) => p == playerId);
    if (playerId == null) {
      next.remove(slot);
    } else {
      next[slot] = playerId;
    }
    return copyWith(
      players: next,
      setPieces: setPiecesAmong(setPieces, next.values),
    );
  }

  /// Affida [role] a [playerId] (null = nessuno). Solo un titolare: per chi non è in
  /// campo il ruolo resta libero.
  Formation withSetPiece(SetPiece role, String? playerId) {
    final next = Map.of(setPieces)..remove(role);
    if (playerId != null && players.containsValue(playerId)) {
      next[role] = playerId;
    }
    return copyWith(setPieces: next);
  }
}
