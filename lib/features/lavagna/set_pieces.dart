import '../../core/teams.dart';
import '../formazione/modules.dart';
import '../rosa/member.dart';
import 'board_model.dart';

/// Il "modulo" con cui si salvano gli schemi da palla inattiva (in Tattiche e schemi).
const setPieceModule = 'Piazzati';

/// Un posto dello schema: dove va e chi ci va di preferenza (le sigle dei ruoli della
/// formazione, in ordine), oppure proprio il giocatore di un posto del modulo
/// ([slot]).
class _Spot {
  const _Spot(this.x, this.y, [this.prefs = const [], this.slot]);
  final double x, y;
  final List<String> prefs;
  final int? slot;

  /// Lo stesso posto dall'altra parte del campo (i ruoli di sinistra diventano di
  /// destra).
  _Spot get mirrored =>
      _Spot(1 - x, y, [for (final p in prefs) _mirrorRole[p] ?? p], slot);
}

const _mirrorRole = {
  'TS': 'TD',
  'TD': 'TS',
  'AS': 'AD',
  'AD': 'AS',
  'ES': 'ED',
  'ED': 'ES',
};

const _por = ['POR'];

// Gli schemi sono disegnati sullo schermo, non solo sul campo: il gettone è largo
// l'8,4% della lavagna (circa 0,09 del campo in larghezza e 0,06 in altezza) e sotto
// ha il cognome (alto circa 0,03, largo fino a 0,15). Nessun gettone ne tocca un
// altro, nessun cognome finisce su un gettone o su un altro cognome (anche con i
// cognomi lunghi), le zone di battuta restano libere quanto basta per vedersi e il
// portiere sta sopra 0,94, così il suo nome resta nella lavagna.

/// Angolo da sinistra: il battitore alla bandierina e il corto accanto a lui; in area
/// chi attacca il primo palo, chi blocca il portiere, chi va sul dischetto e chi sul
/// secondo palo, partendo appena fuori dalle zone (che così si vedono); uno arriva da
/// dietro sul secondo palo, uno al limite per la respinta, due a coprire.
const _cornerLeft = [
  _Spot(.5, .935, _por),
  _Spot(.071, .065, ['CC', 'COC', 'AS', 'ES', 'AD', 'ED', 'CDC']),
  _Spot(.355, .108, ['ATT', 'DC', 'AS', 'AD']),
  _Spot(.614, .125, ['DC', 'ATT', 'CDC']),
  _Spot(.73, .039, ['DC', 'ATT', 'AD', 'AS']),
  _Spot(.5, .03, ['ATT', 'AS', 'AD', 'COC', 'DC']),
  _Spot(.833, .142, ['CC', 'COC', 'ES', 'ED', 'AD', 'AS']),
  _Spot(.5, .241, ['CDC', 'COC', 'CC']),
  _Spot(.2, .116, ['CC', 'COC', 'AS', 'AD', 'ES', 'ED', 'TS']),
  _Spot(.28, .45, ['TS', 'CDC', 'DC', 'ES']),
  _Spot(.72, .45, ['TD', 'CDC', 'DC', 'ED']),
];

/// Punizione centrale a 25 metri: il battitore e un secondo ai lati del pallone,
/// quattro sulla linea della difesa (al limite dell'area) pronti a entrare sulle zone,
/// il corto vicino alla sua zona, uno sulla seconda palla, due dietro.
const _freeKick = [
  _Spot(.5, .935, _por),
  _Spot(.415, .262, ['COC', 'CC', 'AS', 'AD', 'ATT']),
  _Spot(.585, .262, ['CC', 'COC', 'AD', 'AS']),
  _Spot(.165, .15, ['DC', 'ATT', 'AS']),
  _Spot(.325, .15, ['ATT', 'DC']),
  _Spot(.675, .15, ['DC', 'ATT']),
  _Spot(.835, .15, ['AS', 'AD', 'ATT', 'DC', 'COC']),
  _Spot(.8, .3, ['AD', 'ED', 'CC']),
  _Spot(.5, .38, ['CDC', 'CC']),
  _Spot(.28, .5, ['TS', 'DC', 'CDC']),
  _Spot(.72, .5, ['TD', 'DC', 'CDC']),
];

/// Rigore: il battitore dietro il pallone, quattro sulla linea dell'area (fuori anche
/// dalla lunetta) pronti sulla ribattuta, uno sulla seconda palla, quattro dietro.
const _penalty = [
  _Spot(.5, .935, _por),
  _Spot(.5, .15, ['ATT', 'COC', 'AS', 'AD', 'CC']),
  _Spot(.33, .16, ['ATT', 'AS', 'AD', 'COC', 'DC']),
  _Spot(.67, .16, ['AS', 'AD', 'ATT', 'COC', 'DC']),
  _Spot(.17, .16, ['DC', 'AS', 'CC']),
  _Spot(.83, .16, ['DC', 'AD', 'CC']),
  _Spot(.5, .25, ['COC', 'CC', 'CDC']),
  _Spot(.5, .38, ['CDC', 'CC']),
  _Spot(.3, .47, ['TS', 'CDC', 'DC']),
  _Spot(.7, .47, ['TD', 'CDC', 'DC']),
  _Spot(.5, .58, ['DC', 'CDC', 'CC']),
];

/// Rimessa laterale a sinistra nella metà campo avversaria: chi batte sulla linea,
/// tre appoggi (lungo la linea, incontro accanto alla zona del corto, dietro), due ai
/// lati dell'area per la rimessa lunga, uno al limite, il largo dall'altra parte, due
/// a coprire.
const _throwIn = [
  _Spot(.5, .935, _por),
  _Spot(.06, .345, ['TS', 'ES', 'AS', 'CC']),
  _Spot(.1, .2, ['AS', 'ES', 'ATT']),
  _Spot(.27, .33, ['CC', 'COC', 'AS']),
  _Spot(.14, .47, ['CDC', 'CC', 'DC']),
  _Spot(.3, .1, ['ATT', 'DC']),
  _Spot(.69, .1, ['DC', 'ATT', 'AD']),
  _Spot(.5, .24, ['COC', 'CC']),
  _Spot(.85, .32, ['AD', 'ED', 'TD']),
  _Spot(.4, .5, ['DC']),
  _Spot(.62, .52, ['DC', 'TD', 'CDC']),
];

/// Rinvio dal fondo: il portiere accanto al pallone nell'area piccola, i centrali
/// aperti ai lati dell'area, i terzini alti e larghi, il mediano davanti, le mezzali,
/// le ali e la punta a dare profondità.
const _goalKick = [
  _Spot(.56, .935, _por),
  _Spot(.26, .9, ['DC']),
  _Spot(.74, .9, ['DC']),
  _Spot(.06, .72, ['TS', 'ES']),
  _Spot(.94, .72, ['TD', 'ED']),
  _Spot(.5, .8, ['CDC', 'CC']),
  _Spot(.3, .62, ['CC', 'COC', 'CDC']),
  _Spot(.7, .62, ['CC', 'COC', 'CDC']),
  _Spot(.12, .44, ['AS', 'ES', 'AD']),
  _Spot(.88, .44, ['AD', 'ED', 'AS']),
  _Spot(.5, .4, ['ATT', 'COC']),
];

/// Angolo contro (dalla nostra bandierina in basso a sinistra): la zona nella nostra
/// area, con il portiere in mezzo ai pali e due ai lati dell'area piccola; i due
/// centrali al limite ai lati della zona 4, pronti ad attaccare il pallone; due
/// all'altezza dell'area piccola sui lati, uno sul secondo palo lungo, uno sul corto,
/// uno al limite per la respinta, una punta su per la ripartenza.
const _cornerAgainst = [
  _Spot(.5, .94, _por),
  _Spot(.335, .9, ['TS', 'ES', 'CC']),
  _Spot(.665, .9, ['TD', 'ED', 'CC']),
  _Spot(.37, .79, ['DC', 'CDC']),
  _Spot(.63, .79, ['DC', 'CDC']),
  _Spot(.21, .935, ['CDC', 'DC']),
  _Spot(.79, .935, ['CDC', 'CC']),
  _Spot(.82, .79, ['CC', 'COC']),
  _Spot(.08, .84, ['AS', 'ES', 'CC']),
  _Spot(.5, .68, ['COC', 'CC', 'AD']),
  _Spot(.55, .52, ['ATT', 'AD', 'AS']),
];

/// Calcio d'inizio: le posizioni del modulo della squadra, tutte nella nostra metà
/// campo; la punta più centrale sul pallone.
List<_Spot> _kickOff(List<SlotPosition> slots) {
  var kicker = -1;
  for (final label in ['ATT', 'COC', 'AS', 'AD']) {
    for (final (i, s) in slots.indexed) {
      if (s.label == label &&
          (kicker < 0 ||
              (s.x - .5).abs() < (slots[kicker].x - .5).abs() - 1e-9)) {
        kicker = i;
      }
    }
    if (kicker >= 0) break;
  }
  if (kicker < 0) kicker = slots.length - 1;
  return [
    _Spot(slots[0].x, slots[0].y, _por, 0),
    _Spot(.5, .535, const [], kicker),
    for (final (i, s) in slots.indexed)
      if (i != 0 && i != kicker)
        _Spot(s.x, (.53 + (s.y - .16) * .39 / .76).clamp(.53, .92), [], i),
  ];
}

/// Gli schemi pronti da palla inattiva ("Nuova lavagna dal modulo" → "Palle
/// inattive"): pallone sul punto giusto e i nostri undici ai loro posti, con i
/// battitori della formazione pubblicata dove ci sono. [zones]: le zone di battuta si
/// accendono da sole (dove si crossa).
enum SetPieceTemplate {
  angoloSinistra(
    'angolo_sx',
    'Angolo da sinistra',
    taker: SetPiece.angoliSinistra,
    zones: true,
  ),
  angoloDestra(
    'angolo_dx',
    'Angolo da destra',
    taker: SetPiece.angoliDestra,
    zones: true,
  ),
  punizione('punizione', 'Punizione', taker: SetPiece.punizioni, zones: true),
  rigore('rigore', 'Rigore', taker: SetPiece.rigori),
  rimessa('rimessa', 'Rimessa laterale', zones: true),
  rinvio('rinvio', 'Rinvio dal fondo'),
  inizio('inizio', 'Calcio d\'inizio'),
  angoloContro('angolo_contro', 'Angolo contro', zones: true);

  const SetPieceTemplate(
    this.key,
    this.label, {
    this.taker,
    this.zones = false,
  });

  /// Nel JSON ([BoardSetPiece.kind]).
  final String key;
  final String label;

  /// Il ruolo della formazione che batte (il secondo posto dello schema).
  final SetPiece? taker;
  final bool zones;

  static SetPieceTemplate? parse(String? key) =>
      values.where((t) => t.key == key).firstOrNull;

  /// Dove si mette il pallone: le bandierine in alto (in basso la nostra per
  /// "Angolo contro"), 25 metri dalla porta, il dischetto, la linea laterale
  /// sinistra nella loro metà campo, la nostra area piccola, il centrocampo.
  (double, double) get spot => switch (this) {
    angoloSinistra => (.02, .013),
    angoloDestra => (.98, .013),
    punizione => (.5, .24),
    // Due terzi dell'area (0,14): con i tre decimali del JSON.
    rigore => (.5, .093),
    rimessa => (.012, .3),
    rinvio => (.42, .962),
    inizio => (.5, .5),
    angoloContro => (.02, .987),
  };

  /// Gli undici posti: il primo è il portiere, il secondo chi batte.
  List<_Spot> _spots(List<SlotPosition> slots) => switch (this) {
    angoloSinistra => _cornerLeft,
    angoloDestra => [for (final s in _cornerLeft) s.mirrored],
    punizione => _freeKick,
    rigore => _penalty,
    rimessa => _throwIn,
    rinvio => _goalKick,
    inizio => _kickOff(slots),
    angoloContro => _cornerAgainst,
  };
}

/// La lavagna di uno schema da palla inattiva per [team]: i giocatori dalla
/// formazione (quella pubblicata, se c'è, altrimenti la bozza) e chi batte dai
/// battitori pubblicati; dove manca il giocatore resta la sigla del ruolo. I gettoni
/// hanno gli id dei posti del modulo (`f0`...`f10`), come le lavagne dal modulo.
BoardState setPieceBoard(
  SetPieceTemplate template,
  Team team,
  List<Member> rosa,
  Formation? formation,
) {
  final published = formation?.isPublished ?? false;
  final f = published ? formation!.publishedView : formation;
  final slots = formationModules[f?.module] ?? formationModules[defaultModule]!;
  final players = f?.players ?? const <int, String>{};
  final takers = published ? f!.setPieces : const <SetPiece, String>{};
  final spots = template._spots(slots);

  // Prima il battitore scelto dal Direttivo, poi i posti in ordine, ognuno al primo
  // giocatore libero del ruolo che preferisce (o al primo libero).
  final slotOf = List<int?>.filled(spots.length, null);
  final used = <int>{};
  final takerId = template.taker == null ? null : takers[template.taker];
  final takerSlot = players.entries
      .where((e) => e.value == takerId && e.key < slots.length)
      .firstOrNull
      ?.key;
  if (takerSlot != null) {
    slotOf[1] = takerSlot;
    used.add(takerSlot);
  }
  for (final (i, spot) in spots.indexed) {
    if (slotOf[i] != null) continue;
    int? free(bool Function(int j) ok) {
      for (var j = 1; j < slots.length; j++) {
        if (!used.contains(j) && ok(j)) return j;
      }
      return used.contains(0) || !ok(0) ? null : 0;
    }

    final fixed = spot.slot;
    final pick =
        (fixed != null && !used.contains(fixed) ? fixed : null) ??
        spot.prefs
            .map((label) => free((j) => slots[j].label == label))
            .nonNulls
            .firstOrNull ??
        free((_) => true);
    if (pick == null) continue;
    slotOf[i] = pick;
    used.add(pick);
  }

  final (bx, by) = template.spot;
  return BoardState(
    module: setPieceModule,
    team: team.name,
    tokens: [
      for (final (i, spot) in spots.indexed)
        if (slotOf[i] case final j?)
          () {
            final m = rosa.where((x) => x.id == players[j]).firstOrNull;
            // Con i decimali del JSON (i posti specchiati e quelli del calcio
            // d'inizio si calcolano): lo schema è uguale dal vivo e nel replay.
            return BoardToken(
              id: 'f$j',
              x: fieldCoord(spot.x),
              y: fieldCoord(spot.y),
              playerId: m?.id,
              label: m?.shirtNumber?.toString() ?? slots[j].label,
              name: m?.displayName ?? '',
              side: team.name,
            );
          }(),
    ],
    ball: BoardBall(x: bx, y: by),
    piece: BoardSetPiece(kind: template.key, x: bx, y: by),
    view: {if (template.zones) BoardOverlay.zones.key: true},
  );
}
