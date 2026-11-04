import 'package:flutter/foundation.dart';

import 'board_model.dart';

// Quello che la lavagna legge da sola dalle posizioni (zone di battuta, fuorigioco,
// linee di reparto): calcoli puri, il disegno è in board_painter.dart.

/// Una zona di battuta: il numero da gridare in partita, il suo nome e il rettangolo
/// sul campo (centro [x], [y] e misure [w], [h], coordinate 0..1). Il numero sta
/// nell'angolo [badgeX], [badgeY] (verso la porta e il pallone), dove di solito non
/// c'è un gettone.
@immutable
class DeliveryZone {
  const DeliveryZone(
    this.n,
    this.x,
    this.y,
    this.w,
    this.h, {
    required this.badgeX,
    required this.badgeY,
  });
  final int n;
  final double x, y, w, h;
  final double badgeX, badgeY;

  String get name => deliveryZoneNames[n - 1];

  /// Il punto è nella zona (allargata di [slackX] e [slackY] per lato).
  bool contains(double px, double py, {double slackX = 0, double slackY = 0}) =>
      (px - x).abs() <= w / 2 + slackX && (py - y).abs() <= h / 2 + slackY;
}

/// I nomi delle zone di battuta, dalla 1 alla 5: il codice comune che chi batte grida.
const deliveryZoneNames = [
  'primo palo',
  'dischetto',
  'secondo palo',
  'limite dell\'area',
  'corto',
];

/// "1 primo palo · 2 dischetto · ..." (per i suggerimenti).
String get deliveryZoneLegend =>
    [for (final (i, name) in deliveryZoneNames.indexed) '${i + 1} $name']
        .join(' · ');

/// Le cinque zone di battuta nell'area della metà campo dove si batte la palla
/// inattiva dello schema (in alto la loro, in basso la nostra per "Angolo contro"):
/// primo palo dal lato del pallone, il corto accanto a lui. Senza palla inattiva:
/// la loro area, con il primo palo a sinistra.
List<DeliveryZone> deliveryZones(BoardState s) {
  final piece = s.piece;
  final ox = piece?.x ?? 0.0, oy = piece?.y ?? 0.0;
  final bottom = oy > .5, right = ox > .5;
  // Le misure sono per l'area in alto con il primo palo a sinistra: si specchiano.
  double fx(double x) => right ? 1 - x : x;
  double fy(double y) => bottom ? 1 - y : y;
  // Il corto: una decina di metri dal pallone verso l'interno del campo.
  final cx = (fx(ox) + .14).clamp(.07, .93),
      cy = (fy(oy) + .035).clamp(.03, .5);
  // Il numero va in un angolo della zona ([bx], [by]: da che parte), dove negli
  // schemi pronti non c'è un gettone.
  return [
    for (final (n, x, y, w, h, bx, by) in [
      (1, .42, .045, .13, .06, -1, -1),
      (2, .5, .105, .15, .045, 1, -1),
      (3, .59, .048, .14, .066, 1, -1),
      (4, .5, .172, .2, .05, 1, 1),
      (5, cx, cy, .13, .055, 1, 1),
    ])
      DeliveryZone(
        n,
        fx(x),
        fy(y),
        w,
        h,
        badgeX: fx(x + bx * w / 2),
        badgeY: fy(y + by * h / 2),
      ),
  ];
}

/// La zona di battuta in (x, y), se c'è (con un margine per il dito; tra due zone
/// vince quella con il centro più vicino).
DeliveryZone? deliveryZoneAt(
  BoardState s,
  double x,
  double y, {
  double slackX = 0,
  double slackY = 0,
}) {
  DeliveryZone? best;
  var bestD = double.infinity;
  for (final z in deliveryZones(s)) {
    if (!z.contains(x, y, slackX: slackX, slackY: slackY)) continue;
    final d = fieldDistance(z.x - x, z.y - y);
    if (d < bestD) {
      bestD = d;
      best = z;
    }
  }
  return best;
}

/// Il fuorigioco letto dalla lavagna.
@immutable
class OffsideReading {
  const OffsideReading({this.line, this.ourLine, this.flagged = const {}});

  /// La linea del fuorigioco: la y del penultimo avversario contando dalla loro porta
  /// (in alto, portiere compreso). Null con meno di due avversari.
  final double? line;

  /// La nostra linea difensiva: la y del nostro penultimo dalla nostra porta (in
  /// basso). Null con meno di due dei nostri.
  final double? ourLine;

  /// I nostri in fuorigioco: nella metà campo avversaria, oltre la linea e oltre il
  /// pallone (chi ce l'ha al piede no).
  final Set<String> flagged;
}

/// Il fuorigioco: la linea del penultimo avversario e chi dei nostri è oltre lei e
/// oltre il pallone. Chi è alla pari è in gioco; nella propria metà campo non si è mai
/// in fuorigioco.
OffsideReading readOffside(BoardState s) {
  final theirs = [
    for (final t in s.tokens)
      if (t.side == 'avversari') t.y,
  ]..sort();
  final ours = [
    for (final t in s.tokens)
      if (t.side != 'avversari') t,
  ];
  final deep = [for (final t in ours) t.y]..sort((a, b) => b.compareTo(a));
  final line = theirs.length >= 2 ? theirs[1] : null;
  final ball = s.ball;
  return OffsideReading(
    line: line,
    ourLine: deep.length >= 2 ? deep[1] : null,
    flagged: {
      if (line != null)
        for (final t in ours)
          if (t.y < .5 &&
              t.y < line &&
              (ball == null || t.y < ball.y) &&
              t.id != ball?.holder)
            t.id,
    },
  );
}

/// I reparti del modulo ("4-3-3" → [4, 3, 3]); null se non è un modulo (es.
/// "Piazzati").
List<int>? moduleUnits(String module) {
  final parts = [for (final p in module.split('-')) int.tryParse(p.trim())];
  if (parts.length < 2 || parts.any((n) => n == null || n <= 0)) return null;
  return parts.cast<int>();
}

/// Le linee di reparto lette dalla lavagna.
@immutable
class UnitLines {
  const UnitLines(this.groups, this.gapMetres);

  /// I reparti dalla difesa all'attacco, ognuno da sinistra a destra (x, y).
  final List<List<(double, double)>> groups;

  /// I metri tra la difesa e il reparto dopo (media delle y × 105 m).
  final int gapMetres;

  /// La y media di un reparto.
  static double meanY(List<(double, double)> group) =>
      group.fold(0.0, (sum, p) => sum + p.$2) / group.length;
}

/// Le linee di reparto: i nostri gettoni di movimento (il più arretrato è il
/// portiere quando ce n'è uno in più del modulo), dalla nostra porta in su, divisi
/// come dice il modulo. Null se il modulo non è un modulo o i gettoni non tornano.
UnitLines? readUnits(BoardState s) {
  final units = moduleUnits(s.module);
  if (units == null) return null;
  final need = units.fold(0, (a, b) => a + b);
  var ours = [
    for (final t in s.tokens)
      if (t.side != 'avversari') t,
  ]..sort((a, b) => b.y != a.y ? b.y.compareTo(a.y) : a.x.compareTo(b.x));
  if (ours.length == need + 1) ours = ours.sublist(1);
  if (ours.length != need) return null;
  final groups = <List<(double, double)>>[];
  var i = 0;
  for (final n in units) {
    groups.add(
      [for (final t in ours.sublist(i, i + n)) (t.x, t.y)]
        ..sort((a, b) => a.$1.compareTo(b.$1)),
    );
    i += n;
  }
  final gap = (UnitLines.meanY(groups[0]) - UnitLines.meanY(groups[1])) * 105;
  return UnitLines(groups, gap.round());
}
