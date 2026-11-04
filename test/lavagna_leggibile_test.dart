import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/lavagna/board_overlays.dart';
import 'package:milanac/features/lavagna/board_page.dart';
import 'package:milanac/features/lavagna/board_painter.dart';
import 'package:milanac/features/lavagna/set_pieces.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/tattiche/tactics_repository.dart';
import 'package:milanac/shared/ui.dart';

/// La lavagna si legge: negli schemi da palla inattiva nessun gettone tocca un altro
/// e nessun cognome finisce su un gettone o su un altro cognome (anche con undici
/// cognomi lunghi), i numeri delle zone e delle linee stanno dove non coprono niente,
/// le punte non finiscono sui nomi, le linee corte hanno il loro numero, le frecce
/// dei movimenti sono oro. E poi il cross nelle zone, la pressione lunga solo dove
/// serve e il replay uguale al vivo. Le misure dei testi con i caratteri veri
/// (Barlow e Oswald).

Member _member(String id, String name, int number) => Member(
  id: id,
  displayName: name,
  role: ClubRole.giocatore,
  joinedAt: DateTime(2025),
  shirtNumber: number,
);

/// Undici titolari del 4-3-3 con i cognomi di [surnames] (nell'ordine dei posti del
/// modulo) e i battitori pubblicati.
({List<Member> rosa, Formation formation}) _team(List<String> surnames) {
  final rosa = [
    for (final (i, s) in surnames.indexed) _member('g$i', 'Nome $s', i + 1),
  ];
  final players = {for (var i = 0; i < 11; i++) i: 'g$i'};
  const takers = {
    SetPiece.rigori: 'g9',
    SetPiece.punizioni: 'g7',
    SetPiece.angoliSinistra: 'g8',
    SetPiece.angoliDestra: 'g10',
  };
  return (
    rosa: rosa,
    formation: Formation(
      id: 'f',
      players: players,
      setPieces: takers,
      publishedAt: DateTime(2026, 11, 4, 18),
      publishedModule: '4-3-3',
      publishedPlayers: players,
      publishedSetPieces: takers,
    ),
  );
}

/// La rosa della revisione (Esposito, Colombo, Mancini...) e una tutta di cognomi
/// lunghi (larghi quanto "Esposito").
final _rosters = {
  'revisione': _team([
    'Esposito',
    'Romano',
    'Colombo',
    'Ricci',
    'Marino',
    'Greco',
    'Bruno',
    'Gallo',
    'Conti',
    'De Luca',
    'Mancini',
  ]),
  'cognomi lunghi': _team([
    'Esposito',
    'Colombo',
    'Barbieri',
    'Fontana',
    'Santoro',
    'Mancini',
    'Romano',
    'Moretti',
    'Rinaldi',
    'Ferrari',
    'Marino',
  ]),
};

/// Il cerchio [c] di raggio [r] entra nel rettangolo [rect].
bool _circleHitsRect(Offset c, double r, Rect rect) {
  final near = Offset(
    c.dx.clamp(rect.left, rect.right),
    c.dy.clamp(rect.top, rect.bottom),
  );
  return (near - c).distance < r - 1e-6;
}

/// La parte della zona [z] coperta da gettoni e cognomi (da 0 a 1, a campioni).
double _zoneCovered(Size size, BoardState s, DeliveryZone z) {
  final f = BoardPainter.fieldRect(size);
  final c = BoardPainter.toPixel(size, z.x, z.y);
  final w = z.w * f.width, h = z.h * f.height;
  final r = BoardPainter.tokenRadius(size);
  final names = [for (final t in s.tokens) ?BoardPainter.nameRect(size, t)];
  var covered = 0;
  const n = 20;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final p = Offset(
        c.dx - w / 2 + (i + .5) * w / n,
        c.dy - h / 2 + (j + .5) * h / n,
      );
      if (s.tokens.any(
            (t) => (BoardPainter.toPixel(size, t.x, t.y) - p).distance < r,
          ) ||
          names.any((rect) => rect.contains(p))) {
        covered++;
      }
    }
  }
  return covered / (n * n);
}

/// Controlla che sulla lavagna [s], larga [width] pixel, niente si sovrapponga.
void _expectReadable(BoardState s, double width, String what) {
  final size = Size(width, width / boardAspect);
  final board = Offset.zero & size;
  final r = BoardPainter.tokenRadius(size);
  final centres = {
    for (final t in s.tokens) t.id: BoardPainter.toPixel(size, t.x, t.y),
  };
  final names = {
    for (final t in s.tokens) t.id: BoardPainter.nameRect(size, t),
  };
  for (final a in s.tokens) {
    final ca = centres[a.id]!;
    final na = names[a.id];
    expect(na, isNotNull, reason: '$what: ${a.name} ha il cognome');
    expect(
      board.contains(na!.topLeft) && board.contains(na.bottomRight),
      isTrue,
      reason: '$what: il cognome di ${a.name} nella lavagna ($na)',
    );
    for (final b in s.tokens) {
      if (a.id == b.id) continue;
      final cb = centres[b.id]!;
      if (a.id.compareTo(b.id) < 0) {
        expect(
          (ca - cb).distance,
          greaterThanOrEqualTo(2 * r),
          reason: '$what: i gettoni di ${a.name} e ${b.name} si toccano',
        );
        expect(
          na.overlaps(names[b.id]!),
          isFalse,
          reason: '$what: i cognomi di ${a.name} e ${b.name}',
        );
      }
      expect(
        _circleHitsRect(cb, r, na),
        isFalse,
        reason: '$what: il cognome di ${a.name} sul gettone di ${b.name}',
      );
    }
    // Il pallone non copre nessun cognome.
    if (s.ball case final ball?) {
      expect(
        _circleHitsRect(
          BoardPainter.toPixel(size, ball.x, ball.y),
          BoardPainter.ballRadius(size),
          na,
        ),
        isFalse,
        reason: '$what: il pallone sul cognome di ${a.name}',
      );
    }
  }
  // I numeri delle zone: liberi, nella lavagna, e le zone si vedono.
  if (s.shows(BoardOverlay.zones)) {
    final zr = BoardPainter.zoneBadgeRadius(size);
    final badges = BoardPainter.badges(size, s).zones;
    expect(badges.keys, unorderedEquals([1, 2, 3, 4, 5]));
    for (final MapEntry(key: n, value: at) in badges.entries) {
      expect(
        board.deflate(zr).contains(at),
        isTrue,
        reason: '$what: il numero della zona $n nella lavagna',
      );
      for (final t in s.tokens) {
        expect(
          (at - centres[t.id]!).distance,
          greaterThanOrEqualTo(r + zr),
          reason: '$what: il numero della zona $n sul gettone di ${t.name}',
        );
        expect(
          _circleHitsRect(at, zr, names[t.id]!),
          isFalse,
          reason: '$what: il numero della zona $n sul cognome di ${t.name}',
        );
      }
    }
    for (final z in deliveryZones(s)) {
      expect(
        _zoneCovered(size, s, z),
        lessThan(.6),
        reason: '$what: la zona ${z.n} si vede',
      );
    }
  }
}

class _FakeMic implements VoiceRecorder {
  bool _on = false;

  @override
  bool get isRecording => _on;

  @override
  Future<bool> hasPermission({bool request = false}) async => true;

  @override
  Future<bool> start({bool requestPermission = true}) async => _on = true;

  @override
  Future<({Uint8List bytes, int seconds, String path})?> stop({
    int maxSeconds = 120,
    bool keepFile = false,
  }) async {
    _on = false;
    return null;
  }

  @override
  Future<void> cancel() async => _on = false;

  @override
  void dispose() {}
}

/// La lavagna (nuova dal modulo, o lo schema [board]) su un telefono da 360 dp.
Future<void> _openBoard(
  WidgetTester tester, {
  BoardState? board,
  bool readOnly = false,
  double width = 360,
  double height = 780,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final mic = _FakeMic();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [replayMicProvider.overrideWithValue(() => mic)],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: board == null
            ? const BoardPage()
            : BoardPage(
                tactic: Tactic(id: 't', title: 'Schema', board: board),
                readOnly: readOnly,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BoardCanvas _canvas(WidgetTester tester) => tester.widget<BoardCanvas>(
  find.byKey(const ValueKey('lavagna'), skipOffstage: false),
);

BoardState _live(WidgetTester tester) => _canvas(tester).board.value;

Offset _at(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byKey(const ValueKey('lavagna')));
  final f = rect.deflate(rect.width * .028);
  return Offset(f.left + x * f.width, f.top + y * f.height);
}

/// Il compagno sotto il dito in (x, y), come lo cerca la lavagna (entro 1,1 raggi).
BoardToken? _mateAt(WidgetTester tester, BoardState s, double x, double y) {
  final rect = tester.getRect(find.byKey(const ValueKey('lavagna')));
  final reach = BoardPainter.tokenRadius(rect.size) * 1.1;
  final p = _at(tester, x, y);
  BoardToken? best;
  var bestD = reach;
  for (final t in s.tokens) {
    final d = (_at(tester, t.x, t.y) - p).distance;
    if (d < bestD) {
      bestD = d;
      best = t;
    }
  }
  return best?.side == 'avversari' ? null : best;
}

/// La lavagna disegnata da [painter], in pixel.
Future<(ByteData, int)> _pixels(BoardPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return (data, size.width.round());
}

(int, int, int) _rgb((ByteData, int) px, Offset p) {
  final (data, width) = px;
  final i = (p.dy.round() * width + p.dx.round()) * 4;
  return (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

String _json(BoardState s) => jsonEncode(s.toJson());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('it');
    for (final family in [bodyFont, sportFont]) {
      final loader = FontLoader(family);
      for (final w in ['400', '500', '600', '700']) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
      }
      await loader.load();
    }
  });

  group('schemi da palla inattiva disegnati per lo schermo', () {
    for (final MapEntry(key: name, value: team) in _rosters.entries) {
      for (final t in SetPieceTemplate.values) {
        test('${t.label}, rosa "$name": niente si sovrappone', () {
          final s = setPieceBoard(t, Team.milanac, team.rosa, team.formation);
          expect(s.tokens, hasLength(11));
          // Il portiere con il nome nella lavagna; chi batte con il suo.
          final gk = s.tokens.first;
          expect(gk.y, inInclusiveRange(.06, .94), reason: 'il portiere');
          expect(s.tokens[1].name, isNotEmpty, reason: 'chi batte');
          for (final width in [360.0, 328.0, 288.0]) {
            _expectReadable(s, width, '${t.label} a ${width.toInt()} px');
          }
        });
      }
    }

    test('calcio d\'inizio con ogni modulo: i gettoni non si toccano', () {
      const size = Size(360, 360 / boardAspect);
      final r = BoardPainter.tokenRadius(size);
      for (final module in formationModules.keys) {
        final f = Formation(
          id: 'f',
          module: module,
          players: const {},
          publishedAt: DateTime(2026, 11, 4),
          publishedModule: module,
          publishedPlayers: const {},
        );
        final s = setPieceBoard(SetPieceTemplate.inizio, Team.milanac, [], f);
        for (final a in s.tokens) {
          for (final b in s.tokens) {
            if (a.id.compareTo(b.id) >= 0) continue;
            expect(
              (BoardPainter.toPixel(size, a.x, a.y) -
                      BoardPainter.toPixel(size, b.x, b.y))
                  .distance,
              greaterThanOrEqualTo(2 * r),
              reason: '$module: ${a.label} e ${b.label}',
            );
          }
        }
      }
    });

    test('le coordinate degli schemi hanno i decimali del JSON', () {
      final team = _rosters['revisione']!;
      for (final t in SetPieceTemplate.values) {
        final s = setPieceBoard(t, Team.milanac, team.rosa, team.formation);
        expect(_json(canonicalBoard(s)), _json(s));
        for (final k in s.tokens) {
          expect((k.x, k.y), (fieldCoord(k.x), fieldCoord(k.y)), reason: k.id);
        }
      }
    });
  });

  group('numeri e punte delle linee', () {
    /// Il 4-3-3 della revisione e un'azione: retropassaggio, conduzione, passaggi
    /// corti, nello spazio e tiro.
    BoardState sequence() {
      final team = _rosters['revisione']!;
      final slots = formationModules['4-3-3']!;
      final board = BoardState(
        tokens: [
          for (final (i, s) in slots.indexed)
            BoardToken(
              id: 'f$i',
              x: s.x,
              y: s.y,
              playerId: 'g$i',
              label: '${i + 1}',
              name: team.rosa[i].displayName,
            ),
        ],
        ball: BoardBall.kickOff,
      );
      final e = BoardEditor(board)
        ..apply(const GrabBall())
        ..apply(const MoveBall(.5, .56))
        ..apply(const DropBall('f6'))
        ..apply(const KickBall(x: .37, y: .76, to: 'f2'))
        ..apply(const KickBall(x: .12, y: .72, to: 'f1'))
        ..apply(const DragStart('f1'))
        ..apply(const MoveToken('f1', .12, .45))
        ..apply(const DragEnd())
        ..apply(const KickBall(x: .25, y: .5, to: 'f5'))
        ..apply(const KickBall(x: .18, y: .24, to: 'f8'))
        ..apply(const KickBall(x: .35, y: .1))
        ..apply(const KickBall(x: .47, y: 0, shot: true));
      final s = e.state;
      e.dispose();
      return s;
    }

    test('ogni linea ha il suo numero, vicino a lei e senza coprire gettoni, '
        'cognomi o il pallone', () {
      final s = sequence();
      expect([for (final l in s.lines) l.n], [1, 2, 3, 4, 5, 6, 7]);
      for (final width in [360.0, 288.0]) {
        final size = Size(width, width / boardAspect);
        final r = BoardPainter.tokenRadius(size);
        final b = BoardPainter.lineBadgeRadius(size);
        final badges = BoardPainter.badges(size, s).lines;
        expect(badges.keys, unorderedEquals([1, 2, 3, 4, 5, 6, 7]));
        for (final l in s.lines) {
          final at = badges[l.n]!;
          for (final t in s.tokens) {
            final c = BoardPainter.toPixel(size, t.x, t.y);
            expect(
              (at - c).distance,
              greaterThanOrEqualTo(r + b),
              reason: 'linea ${l.n} sul gettone di ${t.name} ($width)',
            );
            expect(
              _circleHitsRect(at, b, BoardPainter.nameRect(size, t)!),
              isFalse,
              reason: 'linea ${l.n} sul cognome di ${t.name} ($width)',
            );
          }
          final ball = s.ball!;
          expect(
            (at - BoardPainter.toPixel(size, ball.x, ball.y)).distance,
            greaterThanOrEqualTo(b + BoardPainter.ballRadius(size)),
          );
          for (final o in s.lines) {
            if (o.n <= l.n) continue;
            expect((at - badges[o.n]!).distance, greaterThanOrEqualTo(2 * b));
          }
          // Vicino alla sua linea (dritta qui: la distanza dal segmento).
          final p1 = BoardPainter.toPixel(size, l.x1, l.y1);
          final p2 = BoardPainter.toPixel(size, l.x2, l.y2);
          final d = p2 - p1;
          final f = d.distanceSquared == 0
              ? 0.0
              : (((at - p1).dx * d.dx + (at - p1).dy * d.dy) /
                        d.distanceSquared)
                    .clamp(0.0, 1.0);
          expect(
            (at - (p1 + d * f)).distance,
            lessThan(b * 4),
            reason: 'il numero ${l.n} vicino alla sua linea',
          );
        }
      }
    });

    test('la punta di una linea che arriva da sotto si ferma sotto il cognome; '
        'una che parte verso il basso esce sotto il cognome', () {
      const size = Size(360, 360 / boardAspect);
      const top = BoardToken(
        id: 'a',
        x: .5,
        y: .3,
        label: '9',
        name: 'Esposito',
      );
      const low = BoardToken(
        id: 'b',
        x: .5,
        y: .6,
        label: '4',
        name: 'Colombo',
      );
      final e = BoardEditor(
        BoardState(tokens: const [top, low], ball: ballAtFeet(low)),
      )..apply(const KickBall(x: .5, y: .3, to: 'a'));
      final up = e.state;
      final tip = BoardPainter.lineSpans(size, up)[1]!.tip;
      final name = BoardPainter.nameRect(size, top)!;
      expect(tip.dy, greaterThan(name.bottom), reason: 'sotto il nome');
      // Senza i nomi (anteprime) la punta arriva al gettone.
      final bare = BoardPainter.lineSpans(size, up, showNames: false)[1]!.tip;
      expect(bare.dy, lessThan(name.top + 1));
      // E all'indietro: la palla torna giù, la linea parte sotto il cognome.
      e.apply(const KickBall(x: .5, y: .6, to: 'b'));
      final down = BoardPainter.lineSpans(size, e.state)[2]!;
      expect(down.start.dy, greaterThan(name.bottom), reason: 'sotto il nome');
      expect(
        down.tip.dy,
        lessThan(BoardPainter.toPixel(size, low.x, low.y).dy),
        reason: 'la punta arriva sopra il gettone',
      );
      e.dispose();
    });

    test('una linea corta ha il suo tratto e il suo numero', () async {
      const size = Size(900, 900 / boardAspect);
      // Due compagni a sette metri: tra i gettoni resta un filo d'erba.
      const a = BoardToken(id: 'a', x: .45, y: .5, label: '6');
      const b = BoardToken(id: 'b', x: .55, y: .5, label: '8');
      final e = BoardEditor(
        BoardState(tokens: const [a, b], ball: ballAtFeet(a)),
      )..apply(const KickBall(x: .55, y: .5, to: 'b'));
      var s = e.state;
      expect(BoardPainter.badges(size, s).lines.keys, [1]);
      var px = await _pixels(BoardPainter(s), size);
      final gap = BoardPainter.toPixel(size, .5, .5);
      final (r, g, bl) = _rgb(px, gap);
      expect(min(r, min(g, bl)), greaterThan(150), reason: 'il tratto bianco');
      // Un passaggio corto nello spazio da palla libera: si vede anche lui.
      e
        ..apply(const PlaceBall(BoardBall(x: .3, y: .8)))
        ..apply(const KickBall(x: .3, y: .78));
      s = e.state;
      expect(BoardPainter.badges(size, s).lines.keys, unorderedEquals([1, 2]));
      final span = BoardPainter.lineSpans(size, s)[2]!;
      expect(
        (span.tip - span.start).distance,
        greaterThan(BoardPainter.ballRadius(size)),
      );
      px = await _pixels(BoardPainter(s), size);
      final mid = BoardPainter.toPixel(size, .3, .79);
      final (r2, g2, b2) = _rgb(px, mid);
      expect(
        min(r2, min(g2, b2)),
        greaterThan(150),
        reason: 'il tratto bianco',
      );
      e.dispose();
    });

    test(
      'le frecce dei movimenti sono oro, le linee della palla bianche',
      () async {
        const size = Size(900, 900 / boardAspect);
        const s = BoardState(
          arrows: [BoardArrow(x1: .25, y1: .7, x2: .25, y2: .3)],
          lines: [
            BallLine(
              kind: BallLineKind.pass,
              n: 1,
              x1: .75,
              y1: .7,
              x2: .75,
              y2: .3,
            ),
          ],
        );
        final px = await _pixels(const BoardPainter(s), size);
        final (ar, ag, ab) = _rgb(px, BoardPainter.toPixel(size, .25, .45));
        expect(ar - ab, greaterThan(60), reason: 'oro ($ar, $ag, $ab)');
        expect(ag - ab, greaterThan(30), reason: 'oro ($ar, $ag, $ab)');
        final (lr, lg, lb) = _rgb(px, BoardPainter.toPixel(size, .75, .45));
        expect(min(lr, min(lg, lb)), greaterThan(200), reason: 'bianco');
        expect(movementArrowColor, MilanacColors.goldLight);
      },
    );

    test('le spunte delle zone salvate solo per chi le salva', () async {
      const size = Size(300, 300 / boardAspect);
      final e = BoardEditor(demoZoneBoard());
      final s = e.state;
      expect(s.positions, isNotEmpty);
      final plain = await _pixels(BoardPainter(s), size);
      final checks = await _pixels(BoardPainter(s, showSavedZones: true), size);
      bool same((ByteData, int) a, (ByteData, int) b) {
        final x = a.$1.buffer.asUint8List(), y = b.$1.buffer.asUint8List();
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) return false;
        }
        return true;
      }

      expect(same(plain, checks), isFalse, reason: 'le spunte si vedono');
      e.dispose();
    });
  });

  group('cross nelle zone di battuta', () {
    final team = _rosters['revisione']!;
    for (final t in [
      SetPieceTemplate.angoloSinistra,
      SetPieceTemplate.angoloDestra,
      SetPieceTemplate.punizione,
      SetPieceTemplate.angoloContro,
    ]) {
      testWidgets('${t.label}: un tocco al centro di ogni zona è un cross', (
        tester,
      ) async {
        await _openBoard(
          tester,
          board: setPieceBoard(t, Team.milanac, team.rosa, team.formation),
        );
        await tester.tap(find.text('Pallone'));
        await tester.pumpAndSettle();
        final start = _live(tester);
        for (final z in deliveryZones(start)) {
          final mate = _mateAt(tester, start, z.x, z.y);
          await tester.tapAt(_at(tester, z.x, z.y));
          await tester.pumpAndSettle();
          final s = _live(tester);
          final line = s.lines.single;
          expect(
            (line.kind, line.n),
            (BallLineKind.cross, 1),
            reason: 'zona ${z.n}',
          );
          if (mate != null) {
            // Il compagno che sta lì riceve la palla.
            expect(s.ball!.holder, mate.id, reason: 'zona ${z.n}');
            expect(line.toPlayer, isTrue);
            expect((line.x2, line.y2), (mate.x, mate.y));
          } else {
            // Nessuno: la palla resta libera dove si è toccato.
            expect(s.ball!.holder, isNull, reason: 'zona ${z.n}');
            expect(s.ball!.x, closeTo(z.x, .003), reason: 'zona ${z.n}');
            expect(s.ball!.y, closeTo(z.y, .003), reason: 'zona ${z.n}');
          }
          await tester.tap(find.text('Annulla'));
          await tester.pumpAndSettle();
          expect(_json(_live(tester)), _json(start));
        }
        expect(tester.takeException(), isNull);
      });
    }

    // Il primo e il secondo palo sono vicini alla porta: prima la zona, poi la
    // porta (un tocco lì era un tiro).
    for (final (t, x, y, zone) in [
      (SetPieceTemplate.angoloSinistra, .44, .025, 1),
      (SetPieceTemplate.angoloSinistra, .56, .03, 3),
      (SetPieceTemplate.angoloDestra, .44, .03, 3),
      (SetPieceTemplate.angoloDestra, .56, .025, 1),
    ]) {
      testWidgets('${t.label}: la zona $zone accanto alla porta è un cross, '
          'non un tiro', (tester) async {
        await _openBoard(
          tester,
          board: setPieceBoard(t, Team.milanac, team.rosa, team.formation),
        );
        await tester.tap(find.text('Pallone'));
        await tester.pumpAndSettle();
        final z = deliveryZones(_live(tester))[zone - 1];
        expect(z.contains(x, y), isTrue);
        await tester.tapAt(_at(tester, x, y));
        await tester.pumpAndSettle();
        final s = _live(tester);
        expect(s.lines.single.kind, BallLineKind.cross);
        expect(s.ball!.y, greaterThan(0), reason: 'non in porta');
      });
    }

    testWidgets('fuori dalle zone la porta resta un tiro', (tester) async {
      await _openBoard(
        tester,
        board: setPieceBoard(
          SetPieceTemplate.rigore,
          Team.milanac,
          team.rosa,
          team.formation,
        ),
      );
      expect(_live(tester).shows(BoardOverlay.zones), isFalse);
      await tester.tap(find.text('Pallone'));
      await tester.pumpAndSettle();
      await tester.tapAt(_at(tester, .52, 0));
      await tester.pumpAndSettle();
      expect(_live(tester).lines.single.kind, BallLineKind.shot);
    });
  });

  group('pressione lunga solo con "Gettoni"', () {
    /// Il dito fermo [hold] sul punto (x, y), poi in su a piccoli passi.
    Future<void> holdAndDrag(
      WidgetTester tester,
      double x,
      double y, {
      Duration hold = const Duration(milliseconds: 600),
    }) async {
      final start = _at(tester, x, y);
      final g = await tester.startGesture(start);
      await tester.pump(hold);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(start + Offset(0, -15.0 * i));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('Pallone: il dito fermo 600 ms poi trascina e conduce', (
      tester,
    ) async {
      await _openBoard(tester);
      await tester.tap(find.text('Pallone'));
      await tester.pumpAndSettle();
      // Il CDC riceve la palla, poi la porta avanti partendo da fermo.
      final cdc = _live(tester).tokenById('f6')!;
      await tester.tapAt(_at(tester, cdc.x, cdc.y));
      await tester.pumpAndSettle();
      expect(_live(tester).ball!.holder, 'f6');
      await holdAndDrag(tester, cdc.x, cdc.y);
      final s = _live(tester);
      expect(find.text('Rimetti il pallone a centrocampo'), findsNothing);
      expect(s.tokenById('f6')!.y, lessThan(cdc.y - .1));
      expect(s.ball!.holder, 'f6');
      expect(s.lines.last.kind, BallLineKind.carry);
    });

    testWidgets('Fuoco: il dito fermo 600 ms poi la heatmap', (tester) async {
      await _openBoard(tester);
      await tester.tap(find.text('Fuoco'));
      await tester.pumpAndSettle();
      await holdAndDrag(tester, .3, .6);
      expect(_live(tester).heat.length, greaterThan(3));
      expect(_live(tester).tokens, hasLength(11), reason: 'nessuno tolto');
    });

    testWidgets('Gettoni: tenere premuto toglie il gettone', (tester) async {
      await _openBoard(tester);
      final cdc = _live(tester).tokenById('f6')!;
      await tester.longPressAt(_at(tester, cdc.x, cdc.y));
      await tester.pumpAndSettle();
      expect(_live(tester).tokenById('f6'), isNull);
    });
  });

  group('replay uguale al vivo', () {
    test('la palla lasciata a 0,3334: stessa zona dal vivo e nella chat', () {
      var now = 0;
      final editor = BoardEditor(demoZoneBoard());
      final rec = editor.startRecording(clock: () => now);
      for (final c in const [GrabBall(), MoveBall(.3334, .5), DropBall()]) {
        now += 100;
        editor.apply(c);
      }
      final data = rec.finish(now + 100);
      final chat = ReplayData.fromBytes(data.toBytes()).finalState;
      expect(_json(chat), _json(editor.state));
      expect(editor.state.ball!.x, chat.ball!.x);
      expect(
        ballZoneAt(editor.state.ball!.x, editor.state.ball!.y),
        ballZoneAt(chat.ball!.x, chat.ball!.y),
      );
      for (final t in editor.state.tokens) {
        final c = chat.tokenById(t.id)!;
        expect((t.x, t.y), (c.x, c.y), reason: t.id);
      }
      editor.dispose();
    });

    test('anche partendo da una lavagna con le coordinate non arrotondate', () {
      var now = 0;
      final editor = BoardEditor(
        BoardState(
          tokens: const [
            BoardToken(id: 'a', x: 1 / 3, y: 2 / 3, label: '4'),
            BoardToken(id: 'b', x: 1 - .415, y: .2, label: '9'),
          ],
          ball: BoardBall(x: 2 / 3, y: 1 / 3),
          view: {BoardOverlay.offside.key: true},
        ),
      );
      final rec = editor.startRecording(clock: () => now);
      expect(_json(canonicalBoard(editor.state)), _json(editor.state));
      // La lavagna è ancora quella: i giocatori di una lavagna nuova che arrivano
      // adesso dalla rete si mettono lo stesso.
      expect(editor.moves, 0);
      for (final c in const <BoardCommand>[
        KickBall(x: 1 / 3, y: 2 / 3, to: 'a'),
        DragStart('a'),
        MoveToken('a', .33337, .45555),
        DragEnd(),
        KickBall(x: .70004, y: .1),
        AddArrow(BoardArrow(x1: .1234, y1: .5678, x2: .3333, y2: .6666)),
        HeatStart(),
        Heat(.11111, .22222),
        HeatEnd(),
      ]) {
        now += 50;
        editor.apply(c);
      }
      final chat = ReplayData.fromBytes(rec.finish(now).toBytes());
      expect(_json(chat.finalState), _json(editor.state));
      expect(chat.finalState.ball!.x, editor.state.ball!.x);
      expect(chat.finalState.tokenById('a')!.x, editor.state.tokenById('a')!.x);
      editor.dispose();
    });
  });

  testWidgets('la squadra sulla lavagna: MILANAC e FUTURO', (tester) async {
    await _openBoard(
      tester,
      board: const BoardState(module: '4-3-3', team: 'futuro'),
    );
    expect(find.text('FUTURO'), findsOneWidget);
    expect(find.text('Futuro'), findsNothing);
    await tester.tap(find.byTooltip('Nuova lavagna dal modulo').first);
    await tester.pumpAndSettle();
    final tabs = tester.widget<SegmentedTabs>(find.byType(SegmentedTabs));
    expect(tabs.labels, ['MILANAC', 'FUTURO']);
  });

  testWidgets('le spunte delle posizioni salvate: per il Direttivo sì, per chi '
      'guarda no', (tester) async {
    await _openBoard(tester, board: demoZoneBoard());
    expect(_canvas(tester).showSavedZones, isTrue);
    await _openBoard(tester, board: demoZoneBoard(), readOnly: true);
    expect(_canvas(tester).showSavedZones, isFalse);
  });
}
