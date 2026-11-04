import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/lavagna/board_page.dart';
import 'package:milanac/features/lavagna/board_painter.dart';
import 'package:milanac/features/lavagna/replay_pages.dart';
import 'package:milanac/features/lavagna/replay_player.dart';
import 'package:milanac/features/tattiche/tactics_repository.dart';

/// Il pallone sulla lavagna: palla al piede, passaggi, conduzioni e tiri con le linee
/// numerate, "Vista", replay. Le misure dei testi con i caratteri veri (Barlow e
/// Oswald), sui telefoni stretti.

const _a = BoardToken(id: 'a', x: .5, y: .7, label: '4');
const _b = BoardToken(id: 'b', x: .3, y: .5, label: '8');
const _c = BoardToken(id: 'c', x: .7, y: .3, label: '9');
const _avv = BoardToken(id: 'x', x: .6, y: .4, label: '1', side: 'avversari');

BoardState _board({BoardBall? ball = BoardBall.kickOff}) =>
    BoardState(tokens: const [_a, _b, _c, _avv], ball: ball);

String _json(BoardState s) => jsonEncode(s.toJson());

/// Il microfono finto della registrazione (replay senza voce).
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

/// La lavagna (di serie nuova, dal modulo) su un telefono largo [width] dp.
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

/// La lavagna viva.
BoardState _live(WidgetTester tester) => _canvas(tester).board.value;

BallFlight? _flight(WidgetTester tester) => _canvas(tester).flight?.value;

/// Il punto (x, y) del campo sullo schermo.
Offset _at(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byKey(const ValueKey('lavagna')));
  final f = rect.deflate(rect.width * .028);
  return Offset(f.left + x * f.width, f.top + y * f.height);
}

Future<void> _tapField(WidgetTester tester, double x, double y) async {
  await tester.tapAt(_at(tester, x, y));
  await tester.pump();
}

/// Un trascinamento vero: il dito si appoggia in [from], supera la soglia e arriva
/// in [to].
Future<void> _drag(
  WidgetTester tester,
  (double, double) from,
  (double, double) to,
) async {
  final start = _at(tester, from.$1, from.$2);
  final end = _at(tester, to.$1, to.$2);
  final g = await tester.startGesture(start);
  await g.moveTo(start + const Offset(0, 40));
  await tester.pump();
  for (var i = 1; i <= 4; i++) {
    await g.moveTo(Offset.lerp(start + const Offset(0, 40), end, i / 4)!);
    await tester.pump();
  }
  await g.up();
  await tester.pumpAndSettle();
}

/// Le etichette della barra degli strumenti si leggono intere (niente puntini, niente
/// testo rimpicciolito).
void _expectToolbarFits(WidgetTester tester) {
  for (final label in [
    'Gettoni',
    'Pallone',
    'Fuoco',
    'Freccia',
    'Annulla',
    'Pulisci',
  ]) {
    final text = find.text(label);
    final p = tester.renderObject<RenderParagraph>(text);
    expect(p.didExceedMaxLines, isFalse, reason: label);
    final box = tester.getSize(
      find.ancestor(of: text, matching: find.byType(FittedBox)),
    );
    expect(box.width, greaterThanOrEqualTo(p.size.width - .01), reason: label);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('it');
    // Nei test il carattere predefinito è un segnaposto: si caricano quelli veri, così
    // le misure dei testi sono quelle del telefono.
    for (final family in [bodyFont, sportFont]) {
      final loader = FontLoader(family);
      for (final w in ['400', '500', '600', '700']) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
      }
      await loader.load();
    }
  });

  test(
    'pallone: lavagna in JSON con pallone, linee e vista (andata e ritorno)',
    () {
      final editor = BoardEditor(_board())
        ..apply(const KickBall(x: .3, y: .5, to: 'b'))
        ..apply(const DragStart('b'))
        ..apply(const MoveToken('b', .3, .3))
        ..apply(const DragEnd())
        ..apply(const KickBall(x: .5, y: 0, shot: true))
        ..apply(const SetView('bl', false));
      final s = editor.state;
      final back = BoardState.fromJson(
        (jsonDecode(_json(s)) as Map).cast<String, dynamic>(),
      );
      expect(_json(back), _json(s));
      expect((back.ball!.x, back.ball!.y, back.ball!.holder), (.5, 0.0, null));
      expect(
        [for (final l in back.lines) l.kind],
        [BallLineKind.pass, BallLineKind.carry, BallLineKind.shot],
      );
      expect([for (final l in back.lines) l.n], [1, 2, 3]);
      expect(back.lines.first.fromPlayer, isFalse); // da palla libera
      expect(back.lines.first.toPlayer, isTrue);
      expect(back.shows(BoardOverlay.ballLines), isFalse);
      expect(back.version, 2);
      // Il pallone al piede resta di chi ce l'ha.
      final held = BoardState.fromJson(
        BoardState(tokens: const [_a], ball: ballAtFeet(_a)).toJson(),
      );
      expect(held.ball!.holder, 'a');
      // Anche l'anteprima del replay in chat li ha (senza heatmap).
      final preview = s.toPreviewJson();
      expect(preview['ball'], isNotNull);
      expect(preview['lines'], hasLength(3));
      expect(preview['view'], {'bl': false});
    },
  );

  test('schema salvato prima del pallone: si apre senza pallone, che non compare da '
      'solo', () {
    final old = <String, dynamic>{
      'module': '4-4-2',
      'team': 'milanac',
      'tokens': [
        {'id': 'f0', 'x': .5, 'y': .92, 'l': '1'},
      ],
      'arrows': <Object>[],
      'heat': [
        [.2, .2],
      ],
    };
    final s = BoardState.fromJson(old);
    expect(s.ball, isNull);
    expect(s.lines, isEmpty);
    expect(s.shows(BoardOverlay.ballLines), isTrue);
    expect(s.version, 1);
    // Salvato di nuovo resta com'era.
    expect(s.toJson().keys, isNot(contains('ball')));
    final editor = BoardEditor(s)
      ..apply(const DragStart('f0'))
      ..apply(const MoveToken('f0', .5, .6))
      ..apply(const DragEnd());
    expect(editor.state.ball, isNull);
    expect(editor.state.lines, isEmpty);

    // Pallone, linee e vista malformati non rovinano lo schema.
    final odd = BoardState.fromJson({
      ...old,
      'ball': 'rotto',
      'lines': [
        {'k': 'zz', 'n': 1, 'x1': 0, 'y1': 0, 'x2': 1, 'y2': 1},
        3,
        {'k': 'p', 'n': 1e300, 'x1': 0, 'y1': 0, 'x2': 1, 'y2': 1},
        {'k': 'p', 'n': double.infinity, 'x1': 0, 'y1': 0, 'x2': 1, 'y2': 1},
      ],
      'view': {'bl': 'no', 'futuro': true},
    });
    expect(odd.tokens, hasLength(1));
    expect(odd.ball, isNull);
    expect(odd.lines.single.n, 99999);
    expect(odd.view, {'futuro': true});

    // copyWith toglie il pallone solo se lo si chiede.
    expect(_board().copyWith(ball: () => null).ball, isNull);
    expect(_board().copyWith(module: '3-5-2').ball, isNotNull);
  });

  test('palla al piede: lasciata su un gettone gli va al piede e lo segue', () {
    final editor = BoardEditor(_board())
      ..apply(const GrabBall())
      ..apply(const MoveBall(.32, .52))
      ..apply(const DropBall('b'));
    var ball = editor.state.ball!;
    expect(ball.holder, 'b');
    expect((ball.x, ball.y), (ballAtFeet(_b).x, ballAtFeet(_b).y));
    expect(ball.x, greaterThan(_b.x)); // accanto al gettone, non sul numero
    expect(editor.state.lines, isEmpty); // spostare il pallone non lascia linee

    // Il giocatore se lo porta dietro; un passo piccolo non lascia la linea.
    editor
      ..apply(const DragStart('b'))
      ..apply(const MoveToken('b', .32, .5))
      ..apply(const DragEnd());
    ball = editor.state.ball!;
    expect(ball.holder, 'b');
    expect(ball.x, closeTo(.32 + .045, 1e-9));
    expect(editor.state.lines, isEmpty, reason: 'sotto la soglia');

    // Una conduzione vera lascia la linea ondulata, dal punto di partenza.
    editor
      ..apply(const DragStart('b'))
      ..apply(const MoveToken('b', .3, .4))
      ..apply(const MoveToken('b', .3, .3))
      ..apply(const DragEnd());
    final carry = editor.state.lines.single;
    expect(carry.kind, BallLineKind.carry);
    expect(carry.n, 1);
    expect((carry.x1, carry.y1, carry.x2, carry.y2), (.32, .5, .3, .3));
    expect(editor.state.ball!.y, closeTo(.3 + .016, 1e-9));

    // Chi non ha la palla si muove senza linee.
    editor
      ..apply(const DragStart('a'))
      ..apply(const MoveToken('a', .5, .3))
      ..apply(const DragEnd());
    expect(editor.state.lines, hasLength(1));

    // Trascinato via si stacca.
    editor
      ..apply(const GrabBall())
      ..apply(const MoveBall(.8, .8))
      ..apply(const DropBall());
    ball = editor.state.ball!;
    expect((ball.x, ball.y, ball.holder), (.8, .8, null));

    // Anche un avversario può avere la palla; tolto lui, resta lì libera.
    editor
      ..apply(const GrabBall())
      ..apply(const MoveBall(.6, .4))
      ..apply(const DropBall('x'));
    expect(editor.state.ball!.holder, 'x');
    final at = editor.state.ball!;
    editor.apply(const RemoveToken('x'));
    ball = editor.state.ball!;
    expect((ball.x, ball.y, ball.holder), (at.x, at.y, null));
    editor.apply(const Undo());
    expect(editor.state.ball!.holder, 'x');

    // Vicino al bordo destro il pallone va dall'altra parte del gettone.
    const edge = BoardToken(id: 'e', x: .97, y: .98);
    final feet = ballAtFeet(edge);
    expect(feet.x, lessThan(edge.x));
    expect(feet.y, lessThan(edge.y));
  });

  test(
    'passaggio a un compagno, nello spazio e tiro: linee numerate e volo del '
    'pallone',
    () {
      final editor = BoardEditor(_board())
        // Da palla libera: parte da dov'è.
        ..apply(const KickBall(x: .5, y: .7, to: 'a'));
      var s = editor.state;
      expect(s.ball!.holder, 'a');
      expect(s.ball!.x, ballAtFeet(_a).x);
      final first = s.lines.single;
      expect(
        (
          first.kind,
          first.n,
          first.x1,
          first.y1,
          first.x2,
          first.y2,
          first.fromPlayer,
          first.toPlayer,
        ),
        (BallLineKind.pass, 1, .5, .5, .5, .7, false, true),
      );
      final kick = editor.lastKick!;
      expect((kick.fromX, kick.fromY, kick.line), (.5, .5, 1));

      // Da un compagno all'altro: la linea parte dal centro di chi passa.
      editor.apply(const KickBall(x: .3, y: .5, to: 'b'));
      expect(editor.lastKick, isNot(same(kick)));
      s = editor.state;
      expect(s.ball!.holder, 'b');
      expect((s.lines.last.x1, s.lines.last.y1), (.5, .7));
      expect(s.lines.last.fromPlayer, isTrue);

      // Nello spazio: il pallone resta libero sull'erba.
      editor.apply(const KickBall(x: .2, y: .2));
      s = editor.state;
      expect((s.ball!.x, s.ball!.y, s.ball!.holder), (.2, .2, null));
      expect(s.lines.last.toPlayer, isFalse);

      // Tiro: finisce in porta.
      editor.apply(const KickBall(x: .51, y: 0, shot: true));
      s = editor.state;
      expect(s.lines.last.kind, BallLineKind.shot);
      expect((s.ball!.x, s.ball!.y, s.ball!.holder), (.51, 0.0, null));
      expect([for (final l in s.lines) l.n], [1, 2, 3, 4]);

      // Senza pallone un passaggio non fa niente (e non si annulla).
      final empty = BoardEditor(const BoardState(tokens: [_a]))
        ..apply(const KickBall(x: .5, y: .7, to: 'a'));
      expect(empty.state.lines, isEmpty);
      expect(empty.canUndo, isFalse);
      expect(empty.lastKick, isNull);
    },
  );

  test('linee del pallone: restano le ultime 30, la numerazione continua', () {
    final editor = BoardEditor(_board(ball: ballAtFeet(_a)));
    for (var i = 0; i < 35; i++) {
      final to = i.isEven ? _b : _a;
      editor.apply(KickBall(x: to.x, y: to.y, to: to.id));
    }
    final lines = editor.state.lines;
    expect(lines, hasLength(BoardState.maxBallLines));
    expect(lines.first.n, 6);
    expect(lines.last.n, 35);
    expect(editor.state.nextBallNumber, 36);
  });

  test('Annulla: ogni azione del pallone si annulla, la vista resta', () {
    final editor = BoardEditor(_board(ball: ballAtFeet(_a)));
    void undoes(String what, List<BoardCommand> commands) {
      final before = _json(editor.state);
      commands.forEach(editor.apply);
      expect(_json(editor.state), isNot(before), reason: what);
      editor.apply(const Undo());
      expect(_json(editor.state), before, reason: what);
      expect(editor.lastKick, isNull, reason: 'niente volo dopo Annulla');
      commands.forEach(editor.apply); // si rifà, per andare avanti
    }

    undoes('passaggio', [const KickBall(x: .3, y: .5, to: 'b')]);
    undoes('nello spazio', [const KickBall(x: .2, y: .2)]);
    undoes('pallone trascinato su un gettone', [
      const GrabBall(),
      const MoveBall(.3, .52),
      const DropBall('b'),
    ]);
    undoes('conduzione', [
      const DragStart('b'),
      const MoveToken('b', .3, .3),
      const DragEnd(),
    ]);
    undoes('tiro', [const KickBall(x: .5, y: 0, shot: true)]);
    undoes('linee cancellate', [const ClearBallLines()]);
    undoes('pallone tolto', [const PlaceBall(null)]);
    undoes('pallone rimesso', [const PlaceBall(BoardBall.kickOff)]);
    undoes('Pulisci', [const Clear()]);

    // La vista non è una mossa: niente passo di "Annulla", e "Annulla" non la tocca.
    editor.apply(const SetView('bl', false));
    editor.apply(const Undo()); // toglie Pulisci
    expect(editor.state.tokens, isNotEmpty);
    expect(editor.state.shows(BoardOverlay.ballLines), isFalse);
    // Rimessa come di serie, non resta scritta.
    editor.apply(const SetView('bl', true));
    expect(editor.state.view, isEmpty);
  });

  test('Pulisci: via linee e gettoni, il pallone torna a centrocampo; la lavagna dal '
      'modulo parte da lì', () {
    final demo = demoBoard();
    expect(demo.ball, isNotNull);
    expect(demo.lines, hasLength(5));
    final editor = BoardEditor(demo)..apply(const Clear());
    var s = editor.state;
    expect(s.isEmpty, isTrue);
    expect(s.lines, isEmpty);
    expect((s.ball!.x, s.ball!.y, s.ball!.holder), (.5, .5, null));
    // Anche uno schema senza pallone, pulito, lo ritrova a centrocampo.
    final old = BoardEditor(const BoardState(tokens: [_a]))
      ..apply(const Clear());
    expect(old.state.ball, isNotNull);

    editor.apply(
      const Reset(BoardState(tokens: [_a], ball: BoardBall.kickOff)),
    );
    s = editor.state;
    expect(s.lines, isEmpty);
    expect((s.ball!.x, s.ball!.y), (.5, .5));
    editor.apply(const Undo());
    expect(editor.state.tokens, isEmpty); // di nuovo la lavagna pulita
  });

  test(
    'replay con il pallone: a ogni istante come dal vivo, anche con Annulla',
    () {
      var now = 0;
      final editor = BoardEditor(demoReplay().initial);
      final rec = editor.startRecording(clock: () => now);
      final script = <(int, BoardCommand)>[
        (500, const KickBall(x: .37, y: .76, to: 't2')),
        (1500, const DragStart('t2')),
        (1600, const MoveToken('t2', .37, .66)),
        (1700, const MoveToken('t2', .4, .55)),
        (1800, const DragEnd()),
        (2500, const KickBall(x: .5, y: .56, to: 't6')),
        (3000, const Undo()),
        (3500, const KickBall(x: .25, y: .5, to: 't5')),
        (4000, const GrabBall()),
        (4100, const MoveBall(.3, .4)),
        (4200, const DropBall()),
        (5000, const KickBall(x: .5, y: .17, to: 't9')),
        (5600, const SetView('bl', false)),
        (6000, const KickBall(x: .5, y: 0, shot: true)),
        (6500, const Undo()),
        (7000, const SetView('bl', true)),
        (7500, const KickBall(x: .48, y: 0, shot: true)),
      ];
      final live = <int, String>{};
      for (final (t, c) in script) {
        now = t;
        editor.apply(c);
        live[t] = _json(editor.state);
      }
      editor.onCommand = null;
      final data = rec.finish(8000);
      expect(data.version, 2);
      final bytes = data.toBytes();
      expect((jsonDecode(utf8.decode(bytes)) as Map)['v'], 2);
      final again = ReplayData.fromBytes(bytes);
      expect(_json(again.finalState), _json(editor.state));
      for (final MapEntry(key: t, value: state) in live.entries) {
        expect(_json(again.stateAt(t)), state, reason: 'a $t ms');
      }
      // Un'azione per passaggio o tiro: il volo non si registra fotogramma per
      // fotogramma.
      expect(again.events.where((e) => e.command is KickBall), hasLength(6));
      expect(bytes.length, lessThan(3000));
    },
  );

  test('replay: il volo del pallone segue il tempo del replay', () async {
    final data = ReplayData(
      initial: BoardState(tokens: const [_a, _b], ball: ballAtFeet(_a)),
      durationMs: 3000,
      events: const [ReplayEvent(1000, KickBall(x: .3, y: .5, to: 'b'))],
    );
    final player = ReplayPlayer(data);
    addTearDown(player.dispose);
    await player.seek(900);
    expect(player.flight.value, isNull);
    expect(player.state.ball!.holder, 'a');
    await player.seek(1000 + ballFlightMs ~/ 3);
    final f = player.flight.value!;
    expect(f.t, closeTo(1 / 3, .01));
    expect((f.kick.fromX, f.kick.fromY), (ballAtFeet(_a).x, ballAtFeet(_a).y));
    expect(player.state.ball!.holder, 'b'); // lo stato è già quello d'arrivo
    await player.seek(1000 + ballFlightMs);
    expect(player.flight.value, isNull);
    // Tornando indietro il volo si rivede, prima del passaggio no.
    await player.seek(1100);
    expect(player.flight.value, isNotNull);
    await player.seek(500);
    expect(player.flight.value, isNull);
    expect(player.state.ball!.holder, 'a');
  });

  test(
    'replay: le azioni sconosciute si saltano, una versione più nuova no',
    () {
      final json = <String, dynamic>{
        'v': 2,
        'ms': 3000,
        'board': const BoardState(tokens: [_a]).toJson(),
        'events': [
          {'t': 100, 'k': 'add', 'token': _b.toJson()},
          // Di una versione futura dell'app.
          {'t': 200, 'k': 'fuorigioco', 'linea': .3},
          {'t': 300, 'k': 'undo'},
        ],
      };
      final data = ReplayData.fromJson(json);
      expect(data.events, hasLength(2));
      expect(data.durationMs, 3000);
      // L'azione sconosciuta non ha un suo passo di "Annulla": si toglie il gettone.
      expect(data.finalState.tokens, hasLength(1));
      expect(BoardCommand.fromJson(const {'k': 'boh'}), isNull);
      expect(
        () => ReplayData.fromJson({
          ...json,
          'v': ReplayData.supportedVersion + 1,
        }),
        throwsA(isA<ReplayTooNew>()),
      );
      // Senza pallone resta alla versione 1; con il pallone (la demo) è la 2.
      const plain = ReplayData(
        initial: BoardState(tokens: [_a]),
        events: [ReplayEvent(10, DragStart('a'))],
        durationMs: 100,
      );
      expect(plain.toJson()['v'], 1);
      expect(demoReplay().toJson()['v'], 2);
      expect(
        demoReplay().finalState.ball!.y,
        0,
      ); // il tiro della demo è in porta
    },
  );

  test('Schemi del club: una riga illeggibile si salta, le altre restano', () {
    final list = readTactics([
      {'id': 'a', 'title': 'Buono', 'board': demoBoard().toJson()},
      {
        'id': 'b',
        'title': 'Rotto',
        'board': {
          'tokens': [
            {'id': 5},
          ],
        },
      },
      {'id': 'c', 'title': null},
      {'id': 'd', 'title': 'Senza lavagna'},
    ]);
    expect([for (final t in list) t.id], ['a', 'd']);
    expect(list.first.board!.ball, isNotNull);
    expect(list.first.board!.lines, hasLength(5));
  });

  testWidgets(
    'Replay di una versione più nuova: "Aggiorna l\'app per vedere questo '
    'replay."',
    (tester) async {
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': ReplayData.supportedVersion + 1,
            'ms': 1000,
            'board': <String, dynamic>{},
            'events': <Object>[],
          }),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(),
            home: ReplayPage(
              message: ChatMessage(
                id: 'r9',
                channelId: 'c-tattiche',
                authorId: 'p2',
                createdAt: DateTime(2026, 11, 4, 20),
                localReplay: bytes,
                meta: const {'type': 'replay', 'title': 'Dal futuro'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Aggiorna l\'app per vedere questo replay.'),
        findsOneWidget,
      );
      expect(find.textContaining('Replay non disponibile'), findsNothing);
      expect(find.text('Riprova'), findsNothing); // riprovare non servirebbe
    },
  );

  for (final (width, height) in [(360.0, 780.0), (320.0, 640.0)]) {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.dark ? 'scuro' : 'chiaro';
      testWidgets(
        'Pallone a ${width.toInt()} dp, tema $theme: palla al piede, passaggio, '
        'conduzione, tiro, Vista',
        (tester) async {
          await _openBoard(
            tester,
            width: width,
            height: height,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          _expectToolbarFits(tester);

          // La lavagna nuova: il pallone sul dischetto del centrocampo.
          var s = _live(tester);
          expect((s.ball!.x, s.ball!.y, s.ball!.holder), (.5, .5, null));
          await tester.tap(find.text('Pallone'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Tocca un compagno'), findsOneWidget);
          _expectToolbarFits(tester); // anche con "Pallone" in grassetto

          // Trascinato sul CDC: gli va al piede.
          await _drag(tester, (.5, .5), (.5, .56));
          s = _live(tester);
          expect(s.ball!.holder, 'f6');
          expect(s.lines, isEmpty);

          // Toccando un compagno gli arriva la palla, in volo.
          await _tapField(tester, .37, .76);
          await tester.pump(const Duration(milliseconds: 100));
          expect(_flight(tester), isNotNull, reason: 'il pallone vola');
          s = _live(tester);
          expect(s.ball!.holder, 'f2'); // lo stato è già quello d'arrivo
          await tester.pumpAndSettle();
          expect(_flight(tester), isNull);
          expect(s.lines.single.kind, BallLineKind.pass);

          // Con "Gettoni" il DC conduce il pallone in avanti.
          await tester.tap(find.text('Gettoni'));
          await tester.pumpAndSettle();
          await _drag(tester, (.37, .76), (.37, .6));
          s = _live(tester);
          final dc = s.tokenById('f2')!;
          expect(dc.y, lessThan(.65));
          expect(s.ball!.holder, 'f2');
          expect(s.ball!.y, closeTo(dc.y + .016, 1e-9));
          expect(s.lines.last.kind, BallLineKind.carry);

          // Tiro: un tocco sulla porta avversaria.
          await tester.tap(find.text('Pallone'));
          await tester.pumpAndSettle();
          await _tapField(tester, .5, 0);
          await tester.pumpAndSettle();
          s = _live(tester);
          expect(s.lines.last.kind, BallLineKind.shot);
          expect((s.ball!.y, s.ball!.holder), (0.0, null));
          expect([for (final l in s.lines) l.n], [1, 2, 3]);

          // Vista: un menu piccolo appeso all'occhio; il tocco su una riga la
          // cambia, il menu si chiude e il campo si vede subito. Le linee si
          // nascondono (non si cancellano) e tornano.
          await tester.tap(find.byTooltip('Vista'));
          await tester.pumpAndSettle();
          expect(find.text('VISTA'), findsOneWidget);
          final menu = tester.getRect(
            find
                .ancestor(
                  of: find.text('VISTA'),
                  matching: find.byType(Material),
                )
                .first,
          );
          final pitch = tester.getRect(find.byKey(const ValueKey('lavagna')));
          // Appeso all'occhio: il campo resta scoperto a sinistra e in basso.
          expect(menu.left, greaterThan(pitch.left + 16));
          expect(menu.bottom, lessThan(pitch.bottom - pitch.height * .25));
          await tester.tap(find.text('Linee della palla'));
          await tester.pumpAndSettle();
          expect(find.text('VISTA'), findsNothing, reason: 'il menu si chiude');
          expect(_live(tester).shows(BoardOverlay.ballLines), isFalse);
          expect(_live(tester).lines, hasLength(3));
          await tester.tap(find.byTooltip('Vista'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Linee della palla'));
          await tester.pumpAndSettle();
          expect(_live(tester).shows(BoardOverlay.ballLines), isTrue);

          // Annulla toglie il tiro: il pallone torna al piede del DC.
          await tester.tap(find.text('Annulla'));
          await tester.pumpAndSettle();
          s = _live(tester);
          expect(s.ball!.holder, 'f2');
          expect(s.lines, hasLength(2));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Pallone: tenerlo premuto non lo toglie; dalle sue opzioni sì, e si annulla',
    (tester) async {
      await _openBoard(tester, width: 320, height: 640);
      await tester.longPressAt(_at(tester, .5, .5));
      await tester.pumpAndSettle();
      expect(find.text('PALLONE'), findsOneWidget);
      expect(_live(tester).ball, isNotNull);
      await tester.tap(find.text('Togli il pallone'));
      await tester.pumpAndSettle();
      expect(_live(tester).ball, isNull);

      // Senza pallone, con "Pallone" il tocco lo rimette.
      await tester.tap(find.text('Pallone'));
      await tester.pumpAndSettle();
      expect(find.textContaining('per mettere il pallone'), findsOneWidget);
      await _tapField(tester, .7, .62);
      await tester.pumpAndSettle();
      var ball = _live(tester).ball!;
      expect(ball.x, closeTo(.7, .01));
      expect(ball.y, closeTo(.62, .01));

      // "Pallone" toccato di nuovo apre le opzioni: di nuovo a centrocampo.
      await tester.tap(find.text('Pallone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimetti il pallone a centrocampo'));
      await tester.pumpAndSettle();
      ball = _live(tester).ball!;
      expect((ball.x, ball.y), (.5, .5));

      // Annulla, un passo alla volta.
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(_live(tester).ball!.x, closeTo(.7, .01));
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(_live(tester).ball, isNull);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(_live(tester).ball, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pulisci: via gettoni e linee, il pallone torna a centrocampo', (
    tester,
  ) async {
    await _openBoard(
      tester,
      page: () => BoardPage(
        tactic: Tactic(id: 't3', title: 'Uscita dal basso', board: demoBoard()),
      ),
    );
    expect(_live(tester).lines, hasLength(5));
    await tester.tap(find.text('Pulisci'));
    await tester.pumpAndSettle();
    expect(find.textContaining('linee della palla'), findsOneWidget);
    expect(find.textContaining('torna a centrocampo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pulisci'));
    await tester.pumpAndSettle();
    final s = _live(tester);
    expect(s.tokens, isEmpty);
    expect(s.lines, isEmpty);
    expect((s.ball!.x, s.ball!.y, s.ball!.holder), (.5, .5, null));
  });

  testWidgets(
    'Schema di prima, senza pallone: lo si mette dal foglio "Aggiungi un gettone"',
    (tester) async {
      final old = demoBoard().copyWith(ball: () => null, lines: const []);
      await _openBoard(
        tester,
        page: () => BoardPage(
          tactic: Tactic(id: 't3', title: 'Di prima', board: old),
        ),
      );
      expect(_live(tester).ball, isNull);
      await _tapField(tester, .7, .62);
      await tester.pumpAndSettle();
      expect(find.text('AGGIUNGI UN GETTONE'), findsOneWidget);
      final tile = find.widgetWithText(ListTile, 'Pallone');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final ball = _live(tester).ball!;
      expect(ball.x, closeTo(.7, .01));
      expect(ball.y, closeTo(.62, .01));
      // Con il pallone in campo il foglio non lo propone più.
      await _tapField(tester, .7, .45);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Pallone'), findsNothing);
    },
  );

  testWidgets(
    'Sola lettura: pallone e linee si vedono, il suggerimento spiega le linee',
    (tester) async {
      await _openBoard(
        tester,
        width: 320,
        height: 640,
        brightness: Brightness.light,
        page: () => BoardPage(
          tactic: Tactic(
            id: 't3',
            title: 'Uscita dal basso',
            board: demoBoard(),
          ),
          readOnly: true,
        ),
      );
      final s = _live(tester);
      expect(s.ball, isNotNull);
      expect(s.lines, hasLength(5));
      expect(find.textContaining('ondulata la conduzione'), findsOneWidget);
      // Bianche le linee della palla, oro le frecce dei movimenti.
      expect(find.textContaining('Linee bianche'), findsOneWidget);
      expect(
        find.textContaining('Frecce\u00a0oro:\u00a0i\u00a0movimenti'),
        findsOneWidget,
      );
      expect(find.text('Pallone'), findsNothing); // niente strumenti
      // La vista si cambia anche guardando soltanto.
      await tester.tap(find.byTooltip('Vista'));
      await tester.pumpAndSettle();
      expect(find.text('VISTA'), findsOneWidget);
      await tester.tap(find.text('Linee della palla'));
      await tester.pumpAndSettle();
      expect(_live(tester).shows(BoardOverlay.ballLines), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Registra con il pallone: il replay finisce come la lavagna, a ogni istante',
    (tester) async {
      await _openBoard(tester);
      await tester.tap(find.text('Pallone'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registra il replay'));
      await tester.pump();
      await _tapField(tester, .37, .76); // al DC, da palla libera
      await tester.pump(const Duration(milliseconds: 600));
      await _drag(tester, (.37, .76), (.3, .55)); // conduzione
      await _tapField(tester, .32, .32); // nello spazio
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Annulla'));
      await tester.pump();
      await _tapField(tester, .5, 0); // tiro
      await tester.pump(const Duration(seconds: 2));
      expect(_live(tester).lines, hasLength(3));
      await tester.tap(find.byTooltip('Ferma la registrazione'));
      await tester.pumpAndSettle();

      final data = tester
          .widget<ReplayPreviewPage>(find.byType(ReplayPreviewPage))
          .data;
      expect(data.version, 2);
      expect(_json(data.finalState), _json(_live(tester)));
      expect(data.events.where((e) => e.command is KickBall), hasLength(3));
      // L'anteprima rifà il volo del tiro come dal vivo (i tempi sono quelli del
      // cronometro vero: qui le azioni sono a pochi millisecondi l'una dall'altra).
      final player = ReplayPlayer(data);
      addTearDown(player.dispose);
      final shot = data.events.lastWhere((e) => e.command is KickBall).t;
      await player.seek(shot);
      expect(player.flight.value?.t, 0);
      await player.seek(shot + ballFlightMs);
      expect(player.flight.value, isNull);
      expect(_json(player.state), _json(data.finalState));
    },
  );
}
