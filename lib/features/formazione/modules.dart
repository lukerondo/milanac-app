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

/// Formazione corrente: modulo + giocatore assegnato a ciascuna delle 11 posizioni.
class Formation {
  const Formation({
    this.id = '',
    this.module = defaultModule,
    this.players = const {},
    this.publishedAt,
    this.updatedAt,
  });

  final String id;
  final String module;

  /// Quando il Direttivo l'ha pubblicata (null = ancora bozza).
  final DateTime? publishedAt;
  final DateTime? updatedAt;

  bool get isPublished => publishedAt != null;

  /// Pubblicata oggi (vale come formazione "di stasera").
  bool get isPublishedToday {
    final p = publishedAt?.toLocal();
    final now = DateTime.now();
    return p != null &&
        p.year == now.year &&
        p.month == now.month &&
        p.day == now.day;
  }

  /// Modificata dopo l'ultima pubblicazione.
  bool get hasUnpublishedChanges =>
      publishedAt != null &&
      updatedAt != null &&
      updatedAt!.isAfter(publishedAt!.add(const Duration(seconds: 2)));

  /// Posizione (es. "CC") del giocatore, o null se in panchina.
  String? positionOf(String playerId) {
    for (final e in players.entries) {
      if (e.value == playerId) return slots[e.key].label;
    }
    return null;
  }

  /// slot (0–10) → id del giocatore.
  final Map<int, String> players;

  List<SlotPosition> get slots =>
      formationModules[module] ?? formationModules[defaultModule]!;

  Formation copyWith({
    String? id,
    String? module,
    Map<int, String>? players,
    DateTime? publishedAt,
    DateTime? updatedAt,
  }) => Formation(
    id: id ?? this.id,
    module: module ?? this.module,
    players: players ?? this.players,
    publishedAt: publishedAt ?? this.publishedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Mette [playerId] nello [slot]; se era già in campo altrove, lo sposta.
  Formation assign(int slot, String? playerId) {
    final next = Map.of(players)..removeWhere((_, p) => p == playerId);
    if (playerId == null) {
      next.remove(slot);
    } else {
      next[slot] = playerId;
    }
    return copyWith(players: next);
  }
}
