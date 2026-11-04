import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/lavagna/board_overlays.dart';
import 'package:milanac/features/lavagna/board_page.dart';
import 'package:milanac/features/lavagna/board_painter.dart';
import 'package:milanac/features/lavagna/replay_player.dart';
import 'package:milanac/features/tattiche/tactics_repository.dart';

/// Fuori possesso sulla lavagna: la linea del fuorigioco, le linee di reparto e le
/// posizioni per zona (anche per chi guarda soltanto). Le misure dei testi con i
/// caratteri veri (Barlow e Oswald), sui telefoni stretti.

String _json(BoardState s) => jsonEncode(s.toJson());

BoardToken _our(String id, double x, double y) =>
    BoardToken(id: id, x: x, y: y, label: id);

BoardToken _their(String id, double x, double y) =>
    BoardToken(id: id, x: x, y: y, label: id, side: 'avversari');

/// I gettoni ai posti di un modulo (il portiere compreso), da noi.
List<BoardToken> _module(String module) => [
  for (final (i, s) in formationModules[module]!.indexed) _our('f$i', s.x, s.y),
];

/// La lavagna delle posizioni per zona: il 4-3-3 con un avversario, il pallone a
/// centrocampo (zona 4) e la modalità accesa.
BoardState _zonesBoard() => BoardState(
  tokens: [..._module('4-3-3'), _their('a1', .5, .3)],
  ball: BoardBall.kickOff,
  view: {BoardOverlay.zonePositions.key: true},
);

/// Trascina il pallone (come fa la lavagna: presa, movimento, rilascio).
void _dragBall(BoardEditor e, double x, double y, [String? to]) => e
  ..apply(const GrabBall())
  ..apply(MoveBall(x, y))
  ..apply(DropBall(to));

/// Trascina un gettone.
void _dragToken(BoardEditor e, String id, double x, double y) => e
  ..apply(DragStart(id))
  ..apply(MoveToken(id, x, y))
  ..apply(const DragEnd());

(double, double) _pos(BoardState s, String id) {
  final t = s.tokenById(id)!;
  return (t.x, t.y);
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

Future<void> _openBoard(
  WidgetTester tester, {
  double width = 360,
  double height = 780,
  Brightness brightness = Brightness.dark,
  Widget Function()? page,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final mic = _FakeMic();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [replayMicProvider.overrideWithValue(() => mic)],
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: page?.call() ?? const BoardPage(),
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

/// Un trascinamento vero, a passi; [settle] aspetta la fine delle animazioni.
Future<void> _drag(
  WidgetTester tester,
  (double, double) from,
  (double, double) to, {
  bool settle = true,
}) async {
  final start = _at(tester, from.$1, from.$2);
  final end = _at(tester, to.$1, to.$2);
  final g = await tester.startGesture(start);
  await g.moveTo(start + const Offset(0, 30));
  await tester.pump();
  for (var i = 1; i <= 4; i++) {
    await g.moveTo(Offset.lerp(start + const Offset(0, 30), end, i / 4)!);
    await tester.pump();
  }
  await g.up();
  if (settle) await tester.pumpAndSettle();
}

/// Accende o spegne un interruttore di "Vista" (il menu si chiude da solo).
Future<void> _toggleView(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Vista'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  expect(find.text('VISTA'), findsNothing);
}

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

  group('fuorigioco', () {
    test('meno di due avversari: niente linea, niente bandierine', () {
      for (final theirs in [
        <BoardToken>[],
        [_their('a', .5, .3)],
      ]) {
        final o = readOffside(
          BoardState(
            tokens: [_our('9', .5, .05), _our('7', .2, .1), ...theirs],
            ball: const BoardBall(x: .5, y: .6),
          ),
        );
        expect(o.line, isNull);
        expect(o.flagged, isEmpty);
        expect(o.ourLine, .05, reason: 'la nostra linea resta');
      }
    });

    test('la linea è il penultimo avversario dalla loro porta, portiere '
        'compreso', () {
      final s = BoardState(
        tokens: [
          _their('gk', .5, .02),
          _their('d1', .3, .4),
          _their('d2', .7, .45),
          _our('9', .5, .3),
        ],
        ball: const BoardBall(x: .5, y: .7),
      );
      final o = readOffside(s);
      expect(o.line, .4, reason: 'non .45: il portiere conta');
      expect(o.flagged, {'9'});
      // Senza il portiere la linea si sposta sull'ultimo difensore.
      expect(
        readOffside(
          s.copyWith(tokens: [...s.tokens.where((t) => t.id != 'gk')]),
        ).line,
        .45,
      );
      // L'ordine dei gettoni non conta.
      expect(
        readOffside(s.copyWith(tokens: s.tokens.reversed.toList())).line,
        .4,
      );
    });

    test('bandierina solo oltre la linea e oltre il pallone, nella loro metà '
        'campo', () {
      final theirs = [_their('gk', .5, .03), _their('d', .4, .3)];
      Set<String> flagged(List<BoardToken> ours, {BoardBall? ball}) =>
          readOffside(BoardState(tokens: [...theirs, ...ours], ball: ball))
              .flagged;

      const back = BoardBall(x: .5, y: .6);
      // Oltre la linea e il pallone: fuorigioco.
      expect(flagged([_our('a', .5, .2)], ball: back), {'a'});
      // In linea: in gioco.
      expect(flagged([_our('a', .5, .3)], ball: back), isEmpty);
      // Dietro la linea: in gioco.
      expect(flagged([_our('a', .5, .35)], ball: back), isEmpty);
      // Dietro il pallone (la palla è più avanti di lui): in gioco.
      expect(
        flagged([_our('a', .5, .2)], ball: const BoardBall(x: .5, y: .1)),
        isEmpty,
      );
      // Senza pallone conta solo la linea.
      expect(flagged([_our('a', .5, .2)]), {'a'});
      // Chi ha la palla al piede non è mai in fuorigioco.
      const holder = BoardToken(id: 'h', x: .5, y: .2);
      expect(flagged([holder], ball: ballAtFeet(holder)), isEmpty);
      // Gli avversari non hanno bandierine (anche oltre la nostra linea).
      expect(flagged([_our('a', .5, .2), _their('z', .9, .95)], ball: back), {
        'a',
      });
      // Nella propria metà campo non si è mai in fuorigioco (difesa avversaria
      // altissima).
      final high = BoardState(
        tokens: [
          _their('gk', .5, .55),
          _their('d', .4, .7),
          _our('a', .5, .6),
          _our('b', .5, .45),
        ],
        ball: const BoardBall(x: .5, y: .9),
      );
      expect(readOffside(high).line, .7);
      expect(readOffside(high).flagged, {'b'});
    });

    test(
      'la nostra linea difensiva: il nostro penultimo dalla nostra porta',
      () {
        final o = readOffside(BoardState(tokens: _module('4-3-3')));
        expect(o.ourLine, .76, reason: 'i centrali, dietro il portiere');
        expect(o.line, isNull);
      },
    );
  });

  group('linee di reparto', () {
    test('i reparti del modulo', () {
      expect(moduleUnits('4-3-3'), [4, 3, 3]);
      expect(moduleUnits('4-1-2-1-2'), [4, 1, 2, 1, 2]);
      expect(moduleUnits(' 3-5-2 '), [3, 5, 2]);
      for (final odd in ['Piazzati', '', '4', '4-x-3', '4--3', '0-5-5']) {
        expect(moduleUnits(odd), isNull, reason: odd);
      }
    });

    test(
      'dalla nostra porta in su, divisi come dice il modulo, con i metri tra '
      'difesa e centrocampo',
      () {
        for (final module in formationModules.keys) {
          final u = readUnits(
            BoardState(module: module, tokens: _module(module)),
          );
          expect(u, isNotNull, reason: module);
          expect(
            [for (final g in u!.groups) g.length],
            moduleUnits(module),
            reason: module,
          );
          // Il portiere non è in nessun reparto.
          for (final g in u.groups) {
            expect(g.any((p) => p.$2 > .9), isFalse, reason: module);
            // Da sinistra a destra.
            expect([
              for (final p in g) p.$1,
            ], [for (final p in g) p.$1]..sort());
          }
        }
        // Il 4-3-3 della demo: difesa a .74, centrocampo a .52 → 23 metri.
        final demo = readUnits(demoBoard())!;
        expect(demo.groups.first, [
          (.12, .72),
          (.37, .76),
          (.63, .76),
          (.88, .72),
        ]);
        expect(demo.groups[1], [(.25, .5), (.5, .56), (.75, .5)]);
        expect(demo.groups.last, [(.18, .24), (.5, .17), (.82, .24)]);
        expect(demo.gapMetres, 23);
        expect(UnitLines.meanY(demo.groups.first), closeTo(.74, 1e-9));
        // Senza portiere (10 gettoni) va bene lo stesso.
        final ten = readUnits(
          BoardState(
            tokens: _module('4-4-2').skip(1).toList(),
            module: '4-4-2',
          ),
        );
        expect([for (final g in ten!.groups) g.length], [4, 4, 2]);
        // Gli avversari non contano.
        final mixed = readUnits(
          BoardState(
            tokens: [..._module('3-5-2'), _their('a', .5, .95)],
            module: '3-5-2',
          ),
        );
        expect([for (final g in mixed!.groups) g.length], [3, 5, 2]);
      },
    );

    test('se i gettoni non tornano col modulo, niente linee', () {
      final tokens = _module('4-3-3');
      expect(readUnits(BoardState(tokens: tokens.take(9).toList())), isNull);
      expect(
        readUnits(BoardState(tokens: [...tokens, _our('x', .5, .5)])),
        isNull,
      );
      expect(readUnits(BoardState(module: 'Piazzati', tokens: tokens)), isNull);
      expect(readUnits(const BoardState()), isNull);
    });

    test('i metri si arrotondano: difesa più alta, reparti più vicini', () {
      final tokens = [
        for (final t in _module('4-4-2'))
          t.y > .9 ? t : t.moved(t.x, t.y > .7 ? .6 : t.y),
      ];
      // Difesa a .6, centrocampo a (.46 + .5 + .5 + .46) / 4 = .48.
      final u = readUnits(BoardState(module: '4-4-2', tokens: tokens))!;
      expect(u.gapMetres, ((.6 - .48) * 105).round());
    });
  });

  group('posizioni per zona', () {
    test('le 9 zone della palla', () {
      expect(ballZoneAt(0, 0), 0);
      expect(ballZoneAt(.5, .5), 4);
      expect(ballZoneAt(1, 1), 8);
      expect(ballZoneAt(.9, .1), 2);
      expect(ballZoneAt(.1, .9), 6);
      expect(ballZoneAt(1 / 3, 2 / 3), 7);
      expect(ballZoneAt(-1, 2), 6, reason: 'fuori dal campo: la più vicina');
      expect(ballZoneName(0), 'Attacco · sinistra');
      expect(ballZoneName(4), 'Centrocampo · centro');
      expect(ballZoneName(8), 'Difesa · destra');
    });

    test('salvate, il pallone che entra nella zona porta lì i giocatori; '
        'annulla, cancella, spenta', () {
      final e = BoardEditor(_zonesBoard())..apply(const SaveZone(4));
      final saved4 = e.state.positions[4]!;
      expect(saved4, hasLength(12), reason: 'anche l\'avversario');
      expect(saved4['f9'], (.5, .17));

      // In attacco a sinistra (zona 0): ancora niente, i giocatori restano.
      _dragBall(e, .15, .15);
      expect(e.lastShift, isNull);
      _dragToken(e, 'f9', .2, .1);
      _dragToken(e, 'a1', .25, .2);
      e.apply(const SaveZone(0));
      expect(e.state.positions.keys, unorderedEquals([0, 4]));

      // Di nuovo a centrocampo: tutti alle posizioni della zona 4.
      _dragBall(e, .5, .45);
      expect(_pos(e.state, 'f9'), (.5, .17));
      expect(_pos(e.state, 'a1'), (.5, .3));
      final shift = e.lastShift!;
      expect(shift.from['f9'], (.2, .1));
      expect(shift.from.keys, unorderedEquals(['f9', 'a1']));

      // Annulla: il trascinamento del pallone torna indietro, giocatori compresi.
      e.apply(const Undo());
      expect(_pos(e.state, 'f9'), (.2, .1));
      expect(e.lastShift, isNull);
      _dragBall(e, .5, .45);

      // Passaggio all'ala sinistra (in zona 0): chi riceve resta dov'è, gli altri
      // vanno alle posizioni della zona 0.
      expect(ballZoneAt(.18 + .045, .24 + .016), 0);
      e.apply(const KickBall(x: .18, y: .24, to: 'f8'));
      expect(e.state.ball!.holder, 'f8');
      expect(_pos(e.state, 'f9'), (.2, .1));
      expect(_pos(e.state, 'f8'), (.18, .24), reason: 'ha la palla');

      // Conduzione verso il centrocampo: lui va dove lo si porta, gli altri seguono
      // la zona 4.
      e
        ..apply(const DragStart('f8'))
        ..apply(const MoveToken('f8', .3, .3))
        ..apply(const MoveToken('f8', .4, .42));
      expect(_pos(e.state, 'f9'), (.5, .17));
      expect(_pos(e.state, 'f8'), (.4, .42));
      e.apply(const DragEnd());
      expect(e.state.lines.last.kind, BallLineKind.carry);

      // Una zona senza posizioni (difesa a destra): nessuno si muove.
      final before = _json(e.state.copyWith(ball: () => null));
      _dragBall(e, .85, .85);
      expect(_json(e.state.copyWith(ball: () => null)), before);

      // Cancellata la zona 0, il pallone lì non muove più nessuno.
      e.apply(const ClearZone(0));
      expect(e.state.positions.keys, [4]);
      _dragBall(e, .1, .1);
      expect(_pos(e.state, 'f9'), (.5, .17));
      e.apply(const Undo());
      e.apply(const Undo());
      expect(e.state.positions.keys, unorderedEquals([0, 4]));

      // Con "Posizioni per zona" spenta il pallone si sposta da solo.
      e.apply(const SetView('pz', false));
      _dragBall(e, .1, .1);
      expect(_pos(e.state, 'f9'), isNot((.2, .1)));
      e.apply(const SetView('pz', true));

      // "Pulisci" porta via anche le posizioni.
      e.apply(const Clear());
      expect(e.state.positions, isEmpty);
      e.apply(const Undo());
      expect(e.state.positions, isNotEmpty);
      e.dispose();
    });

    test(
      'nel JSON (formato 3), malformate si saltano, non nell\'anteprima',
      () {
        final e = BoardEditor(_zonesBoard())
          ..apply(const SaveZone(4))
          ..apply(const SaveZone(8));
        final s = e.state;
        expect(s.version, 3);
        final back = BoardState.fromJson(
          (jsonDecode(_json(s)) as Map).cast<String, dynamic>(),
        );
        expect(_json(back), _json(s));
        expect(back.positions[8]!['f0'], (.5, .92));
        expect(s.toJson()['zones'], isA<Map<String, dynamic>>());
        expect(s.toPreviewJson().keys, isNot(contains('zones')));
        final odd = BoardState.fromJson({
          ...s.toJson(),
          'zones': {
            '4': {
              'f0': [.5, .9],
              'f1': 'rotto',
              'f2': [.1],
              'f3': [double.nan, .5],
              'f4': [2, -1],
            },
            'x': {
              'f0': [.5, .5],
            },
            '9': {
              'f0': [.5, .5],
            },
            '3': 'rotto',
            '5': <String, dynamic>{},
          },
        });
        expect(odd.positions.keys, [4]);
        expect(odd.positions[4], {'f0': (.5, .9), 'f4': (1.0, 0.0)});
        expect(odd.tokens, hasLength(12), reason: 'lo schema si apre');
        // Uno schema senza posizioni resta alla versione 2 e non le scrive.
        expect(_zonesBoard().version, 2);
        expect(_zonesBoard().toJson().keys, isNot(contains('zones')));
        e.dispose();
      },
    );

    test(
      'replay: rifà gli spostamenti uguali a ogni istante, e lo scivolamento '
      'segue il tempo del replay',
      () async {
        var now = 0;
        final e = BoardEditor(_zonesBoard());
        final recorder = e.startRecording(clock: () => now);
        final live = <int, String>{};
        void act(BoardCommand c) {
          now += 1000;
          e.apply(c);
          live[now] = _json(e.state);
        }

        act(const SaveZone(4));
        act(const GrabBall());
        act(const MoveBall(.3, .3));
        act(const MoveBall(.15, .15));
        act(const DropBall());
        act(const DragStart('f9'));
        act(const MoveToken('f9', .2, .1));
        act(const DragEnd());
        act(const SaveZone(0));
        act(const GrabBall());
        act(const MoveBall(.5, .45));
        final shiftAt = now;
        act(const DropBall());
        act(const KickBall(x: .18, y: .24, to: 'f8'));
        act(const Undo());
        act(const ClearZone(0));
        final data = ReplayData.fromBytes(
          recorder.finish(now + 1000).toBytes(),
        );
        expect(
          data.version,
          3,
          reason: 'una versione vecchia direbbe di aggiornare',
        );
        expect(_json(data.finalState), _json(e.state));
        for (final MapEntry(key: t, value: state) in live.entries) {
          expect(_json(data.stateAt(t)), state, reason: 'a $t ms');
        }
        expect(
          data.events.where(
            (x) => x.command is SaveZone || x.command is ClearZone,
          ),
          hasLength(3),
        );

        final player = ReplayPlayer(data);
        addTearDown(player.dispose);
        await player.seek(shiftAt);
        expect(player.shift.value?.t, 0);
        expect(player.shift.value!.shift.from['f9'], (.2, .1));
        await player.seek(shiftAt + zoneShiftMs ~/ 2);
        expect(player.shift.value!.t, closeTo(.5, .01));
        await player.seek(shiftAt + zoneShiftMs);
        expect(player.shift.value, isNull);
        await player.seek(shiftAt - 50);
        expect(player.shift.value, isNull, reason: 'prima non scivola nessuno');
        expect(_pos(player.state, 'f9'), (.2, .1));
        e.dispose();
      },
    );
  });

  test('Vista: gli interruttori si salvano nel JSON, "Annulla" non li tocca, '
      'una lavagna nuova annullata riporta i suoi', () {
    final e = BoardEditor(demoBoard());
    for (final o in [
      BoardOverlay.zones,
      BoardOverlay.offside,
      BoardOverlay.units,
      BoardOverlay.zonePositions,
    ]) {
      expect(e.state.shows(o), isFalse, reason: 'spento di serie: ${o.label}');
    }
    e
      ..apply(const DragStart('t9'))
      ..apply(const MoveToken('t9', .5, .1))
      ..apply(const DragEnd())
      ..apply(const SetView('zb', true))
      ..apply(const SetView('fg', true))
      ..apply(const SetView('lr', true))
      ..apply(const SetView('pz', true));
    expect(e.state.view, {'zb': true, 'fg': true, 'lr': true, 'pz': true});
    final back = BoardState.fromJson(
      (jsonDecode(_json(e.state)) as Map).cast<String, dynamic>(),
    );
    for (final o in BoardOverlay.values) {
      expect(back.shows(o), isTrue, reason: o.label);
    }
    e.apply(const Undo());
    expect(e.state.tokenById('t9')!.y, .17, reason: 'la mossa sì');
    expect(e.state.view, hasLength(4), reason: 'la vista no');
    // Spento di nuovo: tolto dal JSON (uguale a quello di serie).
    e.apply(const SetView('fg', false));
    expect(e.state.view.keys, isNot(contains('fg')));
    // Una lavagna nuova con la sua vista; annullata, torna quella di prima.
    e.apply(Reset(const BoardState(view: {'zb': true})));
    expect(e.state.view, {'zb': true});
    e.apply(const SetView('lr', true));
    e.apply(const Undo());
    expect(e.state.view, {'zb': true, 'lr': true, 'pz': true});
    e.dispose();
  });

  for (final (width, height) in [(360.0, 780.0), (320.0, 640.0)]) {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.dark ? 'scuro' : 'chiaro';
      testWidgets(
        'Posizioni per zona a ${width.toInt()} dp, tema $theme: salva, sposta il '
        'pallone e la squadra lo segue, cancella',
        (tester) async {
          await _openBoard(
            tester,
            width: width,
            height: height,
            brightness: brightness,
          );
          expect(find.text('Salva questa zona'), findsNothing);
          await _toggleView(tester, 'Posizioni per zona');
          expect(_live(tester).shows(BoardOverlay.zonePositions), isTrue);
          expect(
            find.textContaining('Centrocampo · centro · da salvare'),
            findsOneWidget,
          );
          final save = find.text('Salva questa zona');
          expect(save, findsOneWidget);
          final p = tester.renderObject<RenderParagraph>(save);
          expect(p.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);

          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Centrocampo · centro · salvata'),
            findsOneWidget,
          );
          expect(_live(tester).positions.keys, [4]);
          expect(
            find.byTooltip('Cancella le posizioni di questa zona'),
            findsOneWidget,
          );
          // Con il cestino accanto il pulsante resta su una riga, intero.
          final saved = tester.renderObject<RenderParagraph>(
            find.text('Salva questa zona'),
          );
          expect(saved.didExceedMaxLines, isFalse);
          expect(
            saved.size.height,
            lessThan(saved.text.style!.fontSize! * 2),
            reason: 'una riga sola',
          );

          // Il pallone in attacco a sinistra, la punta sul primo palo, si salva.
          await _drag(tester, (.5, .5), (.14, .2));
          expect(
            find.textContaining('Attacco · sinistra · da salvare'),
            findsOneWidget,
          );
          await _drag(tester, (.5, .17), (.3, .08));
          final moved = _pos(_live(tester), 'f9');
          expect(moved.$2, lessThan(.12));
          await tester.tap(find.text('Salva questa zona'));
          await tester.pumpAndSettle();
          expect(_live(tester).positions.keys, unorderedEquals([0, 4]));

          // Il pallone torna a centrocampo: la punta scivola al suo posto.
          final ball = _live(tester).ball!;
          await _drag(tester, (ball.x, ball.y), (.55, .48), settle: false);
          await tester.pump(const Duration(milliseconds: 120));
          expect(_canvas(tester).shift?.value, isNotNull, reason: 'scivolano');
          await tester.pumpAndSettle();
          expect(_canvas(tester).shift?.value, isNull);
          expect(_pos(_live(tester), 'f9'), (.5, .17));

          // E torna dove l'avevamo messa con la palla in attacco.
          await _drag(tester, (.55, .48), (.15, .15));
          expect(_pos(_live(tester), 'f9'), moved);

          // Annulla: il pallone e la squadra tornano a centrocampo.
          await tester.tap(find.text('Annulla'));
          await tester.pumpAndSettle();
          expect(_pos(_live(tester), 'f9'), (.5, .17));

          // Cancella le posizioni della zona del pallone.
          await tester.tap(
            find.byTooltip('Cancella le posizioni di questa zona'),
          );
          await tester.pumpAndSettle();
          expect(_live(tester).positions.keys, [0]);
          expect(
            find.textContaining('Centrocampo · centro · da salvare'),
            findsOneWidget,
          );
          expect(
            find.byTooltip('Cancella le posizioni di questa zona'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);

          // Spenta, la barra se ne va.
          await _toggleView(tester, 'Posizioni per zona');
          expect(find.text('Salva questa zona'), findsNothing);
          expect(_live(tester).positions.keys, [0], reason: 'restano salvate');
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Sola lettura con le posizioni per zona (${brightness.name}): si sposta solo il '
      'pallone, la squadra lo segue, lo schema salvato non cambia',
      (tester) async {
        final board = demoZoneBoard().copyWith(view: const {});
        final saved = _json(board);
        final tactic = Tactic(
          id: 't4',
          title: 'Dove stare con la palla',
          board: board,
        );
        await _openBoard(
          tester,
          width: 320,
          height: 640,
          brightness: brightness,
          page: () => BoardPage(tactic: tactic, readOnly: true),
        );
        expect(
          find.text(
            'Sposta il pallone: vedi dove devi stare quando la palla è in '
            'quella zona.',
          ),
          findsOneWidget,
        );
        expect(find.text('Salva'), findsNothing);
        expect(find.text('Salva questa zona'), findsNothing);
        // La modalità si accende da sola per chi guarda.
        expect(_live(tester).shows(BoardOverlay.zonePositions), isTrue);

        // Il pallone in attacco a destra: tutti alle posizioni della zona 2.
        await _drag(tester, (.5, .5), (.85, .15));
        var s = _live(tester);
        expect(ballZoneAt(s.ball!.x, s.ball!.y), 2);
        for (final t in s.tokens) {
          expect((t.x, t.y), board.positions[2]![t.id], reason: t.id);
        }

        // Un gettone non si sposta, un tocco non fa niente.
        final before = _json(s);
        final nine = s.tokenById('t9')!;
        await _drag(tester, (nine.x, nine.y), (.5, .6));
        await tester.tapAt(_at(tester, .3, .7));
        await tester.longPressAt(_at(tester, nine.x, nine.y));
        await tester.pumpAndSettle();
        expect(_json(_live(tester)), before);

        // In difesa al centro: la squadra si abbassa.
        await _drag(tester, (s.ball!.x, s.ball!.y), (.5, .8));
        s = _live(tester);
        expect(s.tokenById('t9')!.y, board.positions[7]!['t9']!.$2);

        // Lo schema salvato è quello di prima.
        expect(_json(tactic.board!), saved);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Sola lettura senza posizioni per zona: il pallone non si sposta',
    (tester) async {
      await _openBoard(
        tester,
        page: () => BoardPage(
          tactic: Tactic(
            id: 't3',
            title: 'Uscita dal basso',
            board: demoBoard(),
          ),
          readOnly: true,
        ),
      );
      final before = _json(_live(tester));
      await _drag(tester, (.48, 0.01), (.5, .5));
      expect(_json(_live(tester)), before);
      expect(find.textContaining('Sposta il pallone'), findsNothing);
    },
  );

  testWidgets(
    'Fuorigioco e linee di reparto dalla Vista (320 dp, tema chiaro)',
    (tester) async {
      final board = demoBoard().copyWith(
        tokens: [
          ...demoBoard().tokens,
          const BoardToken(
            id: 'a2',
            x: .5,
            y: .02,
            label: '1',
            side: 'avversari',
          ),
        ],
        lines: const [],
      );
      await _openBoard(
        tester,
        width: 320,
        height: 640,
        brightness: Brightness.light,
        page: () => BoardPage(
          tactic: Tactic(id: 't3', title: 'Uscita dal basso', board: board),
        ),
      );
      await _toggleView(tester, 'Fuorigioco');
      await _toggleView(tester, 'Linee di reparto');
      final s = _live(tester);
      expect(s.shows(BoardOverlay.offside), isTrue);
      expect(s.shows(BoardOverlay.units), isTrue);
      // L'avversario a .3 è il penultimo: la punta a .17 è oltre, ma il pallone
      // (in porta) è ancora più avanti; spostato dietro di lui scatta la
      // bandierina.
      expect(readOffside(s).line, .3);
      expect(readOffside(s).flagged, isEmpty);
      await tester.tap(find.text('Pallone'));
      await tester.pumpAndSettle();
      await _drag(tester, (.48, 0.01), (.5, .5));
      expect(readOffside(_live(tester)).flagged, {'t9', 't8', 't10'});
      expect(readUnits(_live(tester))!.gapMetres, 23);
      // Anche nell'immagine dello schema.
      await tester.runAsync(() async {
        final png = await renderBoardImage(_live(tester), width: 300);
        expect(png, isNotEmpty);
      });
      expect(tester.takeException(), isNull);
    },
  );
}
