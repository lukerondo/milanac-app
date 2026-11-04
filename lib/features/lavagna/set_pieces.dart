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

/// Angolo da sinistra: il battitore sulla bandierina, cinque in area sulle zone
/// (primo palo, davanti al portiere, dischetto, secondo palo, inserimento sul
/// secondo), uno al limite, tre a coprire la ripartenza.
const _cornerLeft = [
  _Spot(.5, .9, _por),
  _Spot(.06, .04, ['CC', 'COC', 'AS', 'ES', 'AD', 'ED', 'CDC']),
  _Spot(.41, .055, ['ATT', 'DC', 'AS', 'AD']),
  _Spot(.5, .11, ['DC', 'ATT', 'CDC']),
  _Spot(.63, .06, ['DC', 'ATT', 'AD', 'AS']),
  _Spot(.5, .028, ['ATT', 'AS', 'AD', 'COC', 'DC']),
  _Spot(.71, .125, ['AD', 'ED', 'AS', 'ATT', 'DC', 'COC']),
  _Spot(.46, .2, ['COC', 'CC', 'CDC']),
  _Spot(.3, .42, ['TS', 'CDC', 'DC', 'ES']),
  _Spot(.7, .42, ['TD', 'CDC', 'DC', 'ED']),
  _Spot(.5, .36, ['CDC', 'CC', 'TS', 'TD']),
];

/// Punizione centrale a 25 metri: battitore e un secondo sul pallone, quattro sulla
/// linea della difesa pronti a entrare, il corto, uno sulla seconda palla, due dietro.
const _freeKick = [
  _Spot(.5, .9, _por),
  _Spot(.46, .275, ['COC', 'CC', 'AS', 'AD', 'ATT']),
  _Spot(.55, .275, ['CC', 'COC', 'AD', 'AS']),
  _Spot(.36, .155, ['DC', 'ATT', 'AS']),
  _Spot(.46, .15, ['ATT', 'DC']),
  _Spot(.56, .15, ['DC', 'ATT']),
  _Spot(.66, .155, ['AS', 'AD', 'ATT', 'DC', 'COC']),
  _Spot(.64, .28, ['AD', 'ED', 'CC']),
  _Spot(.5, .37, ['CDC', 'CC']),
  _Spot(.28, .48, ['TS', 'DC', 'CDC']),
  _Spot(.72, .48, ['TD', 'DC', 'CDC']),
];

/// Rigore: il battitore a pochi passi dal dischetto, gli altri fuori dall'area e
/// dalla lunetta pronti sulla ribattuta, uno sulla seconda palla, tre dietro.
const _penalty = [
  _Spot(.5, .9, _por),
  _Spot(.5, .145, ['ATT', 'COC', 'AS', 'AD', 'CC']),
  _Spot(.36, .155, ['ATT', 'AS', 'AD', 'COC', 'DC']),
  _Spot(.64, .155, ['AS', 'AD', 'ATT', 'COC', 'DC']),
  _Spot(.27, .16, ['DC', 'AS', 'CC']),
  _Spot(.73, .16, ['DC', 'AD', 'CC']),
  _Spot(.5, .21, ['COC', 'CC', 'CDC']),
  _Spot(.5, .3, ['CDC', 'CC']),
  _Spot(.3, .45, ['TS', 'CDC', 'DC']),
  _Spot(.7, .45, ['TD', 'CDC', 'DC']),
  _Spot(.5, .55, ['DC', 'CDC', 'CC']),
];

/// Rimessa laterale a sinistra nella metà campo avversaria: chi batte sulla linea,
/// tre appoggi (lungo la linea, incontro, dietro), due in area per la rimessa lunga,
/// uno al limite, il largo dall'altra parte, due a coprire.
const _throwIn = [
  _Spot(.5, .9, _por),
  _Spot(.03, .335, ['TS', 'ES', 'AS', 'CC']),
  _Spot(.12, .22, ['AS', 'ES', 'ATT']),
  _Spot(.15, .335, ['CC', 'COC', 'AS']),
  _Spot(.14, .47, ['CDC', 'CC', 'DC']),
  _Spot(.43, .08, ['ATT', 'DC']),
  _Spot(.52, .12, ['DC', 'ATT', 'AD']),
  _Spot(.47, .23, ['COC', 'CC']),
  _Spot(.85, .32, ['AD', 'ED', 'TD']),
  _Spot(.4, .5, ['DC']),
  _Spot(.62, .52, ['DC', 'TD', 'CDC']),
];

/// Rinvio dal fondo: il portiere sul pallone nell'area piccola, i centrali aperti ai
/// lati dell'area, i terzini alti e larghi, il mediano davanti, le mezzali, le ali e
/// la punta a dare profondità.
const _goalKick = [
  _Spot(.5, .975, _por),
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

/// Angolo contro (dalla nostra bandierina in basso a sinistra): portiere sulla linea,
/// due sui pali, la zona (tre sulla linea dell'area piccola, due all'altezza del
/// dischetto), uno sul corto, uno al limite, una punta su per la ripartenza.
const _cornerAgainst = [
  _Spot(.5, .975, _por),
  _Spot(.415, .972, ['TS', 'ES', 'CC']),
  _Spot(.585, .972, ['TD', 'ED', 'CC']),
  _Spot(.36, .915, ['DC', 'CDC']),
  _Spot(.5, .912, ['DC', 'CDC']),
  _Spot(.64, .915, ['CDC', 'DC']),
  _Spot(.435, .865, ['CDC', 'CC']),
  _Spot(.565, .865, ['CC', 'COC']),
  _Spot(.16, .94, ['AS', 'ES', 'CC']),
  _Spot(.5, .79, ['COC', 'CC', 'AD']),
  _Spot(.55, .56, ['ATT', 'AD', 'AS']),
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
    rigore => (.5, .0933),
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
            return BoardToken(
              id: 'f$j',
              x: spot.x,
              y: spot.y,
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
