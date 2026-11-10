import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/formazione/formation_repository.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/lavagna/board_overlays.dart';
import 'package:milanac/features/lavagna/board_page.dart';
import 'package:milanac/features/lavagna/board_painter.dart';
import 'package:milanac/features/lavagna/replay_pages.dart';
import 'package:milanac/features/lavagna/set_pieces.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/shared/ui.dart';

/// Le palle inattive sulla lavagna: gli schemi pronti con i battitori della formazione
/// pubblicata, le zone di battuta numerate e il cross. Le misure dei testi con i
/// caratteri veri (Barlow e Oswald), sui telefoni stretti.

String _json(BoardState s) => jsonEncode(s.toJson());

Member _member(String id, String name, int number) => Member(
  id: id,
  displayName: name,
  role: ClubRole.giocatore,
  joinedAt: DateTime(2025),
  shirtNumber: number,
);

final _rosa = [
  _member('p4', 'Andrea Neri', 1),
  _member('p3', 'Luca Bianchi', 4),
  _member('demo', 'Demo Direttivo', 10),
  _member('p2', 'Marco Rossi', 9),
];

/// La formazione della demo (4-3-3: Neri in porta, Bianchi DC, il Demo CDC, Rossi
/// punta), pubblicata con i battitori se [published].
Formation _formation({bool published = true}) {
  const players = {0: 'p4', 2: 'p3', 6: 'demo', 9: 'p2'};
  const takers = {
    SetPiece.rigori: 'p2',
    SetPiece.punizioni: 'demo',
    SetPiece.angoliSinistra: 'demo',
    SetPiece.angoliDestra: 'p2',
  };
  return Formation(
    id: 'f',
    players: players,
    setPieces: takers,
    publishedAt: published ? DateTime(2026, 11, 4, 18) : null,
    publishedModule: published ? '4-3-3' : null,
    publishedPlayers: published ? players : null,
    publishedSetPieces: published ? takers : null,
  );
}

/// Il gettone al posto [i] dello schema (0 portiere, 1 chi batte).
BoardToken _spotToken(BoardState s, int i) => s.tokens[i];

class _FakeMic implements VoiceRecorder {
  bool _on = false;

  @override
  bool get isRecording => _on;

  @override
  Future<bool> hasPermission({bool request = false}) async => true;

  @override
  Future<bool> start({
    bool requestPermission = true,
    int maxSeconds = 120,
  }) async => _on = true;

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
  FormationRepository? formations,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final mic = _FakeMic();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        replayMicProvider.overrideWithValue(() => mic),
        if (formations != null)
          formationRepositoryProvider.overrideWithValue(formations),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: const BoardPage(),
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

Future<void> _tapField(WidgetTester tester, double x, double y) async {
  await tester.tapAt(_at(tester, x, y));
  await tester.pump();
}

/// "Nuova lavagna dal modulo" → uno schema da palla inattiva.
Future<void> _pickTemplate(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Nuova lavagna dal modulo').first);
  await tester.pumpAndSettle();
  expect(find.text('PALLE INATTIVE'), findsOneWidget);
  final pill = find.text(label);
  await tester.ensureVisible(pill);
  await tester.pumpAndSettle();
  await tester.tap(pill);
  await tester.pumpAndSettle();
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

  test(
    'schemi da palla inattiva: pallone sul punto giusto e undici gettoni',
    () {
      for (final t in SetPieceTemplate.values) {
        final s = setPieceBoard(t, Team.milanac, _rosa, _formation());
        expect(s.tokens, hasLength(11), reason: t.label);
        expect(
          {for (final x in s.tokens) x.id},
          hasLength(11),
          reason: t.label,
        );
        expect(
          {for (final x in s.tokens) x.id},
          {for (var i = 0; i < 11; i++) 'f$i'},
          reason: 'gli id dei posti del modulo',
        );
        for (final x in s.tokens) {
          expect(x.x, inInclusiveRange(0, 1), reason: '${t.label} ${x.id}');
          expect(x.y, inInclusiveRange(0, 1), reason: '${t.label} ${x.id}');
          expect(x.side, 'milanac');
        }
        expect(s.module, setPieceModule);
        expect(s.piece!.kind, t.key);
        expect((s.ball!.x, s.ball!.y), t.spot);
        expect(s.ball!.holder, isNull, reason: 'si batte da fermo');
        expect((s.piece!.x, s.piece!.y), t.spot);
        expect(s.shows(BoardOverlay.zones), t.zones, reason: t.label);
        expect(s.lines, isEmpty);
        // Il portiere è il primo, in porta (tranne in "Angolo contro" e nel rinvio:
        // anche lì sulla sua linea).
        expect(_spotToken(s, 0).id, 'f0');
        expect(_spotToken(s, 0).y, greaterThan(.85), reason: t.label);
        // Il JSON torna uguale.
        expect(_json(BoardState.fromJson(s.toJson())), _json(s));
      }

      BoardState board(SetPieceTemplate t) =>
          setPieceBoard(t, Team.milanac, _rosa, _formation());
      // Angoli in alto, sulle bandierine.
      final sx = board(SetPieceTemplate.angoloSinistra).ball!;
      expect((sx.x < .05, sx.y < .03), (true, true));
      final dx = board(SetPieceTemplate.angoloDestra).ball!;
      expect((dx.x > .95, dx.y < .03), (true, true));
      // Punizione centrale a circa 25 metri dalla loro porta.
      final fk = board(SetPieceTemplate.punizione).ball!;
      expect(fk.x, .5);
      expect(fk.y * 105, closeTo(25, 1.5));
      // Rigore sul dischetto (a due terzi dell'area, profonda 0,14).
      final pen = board(SetPieceTemplate.rigore);
      expect(pen.ball!.x, .5);
      expect(pen.ball!.y, closeTo(.14 * 2 / 3, .001));
      // Gli altri fuori dall'area e dalla lunetta.
      for (final t in pen.tokens.skip(2)) {
        expect(t.y, greaterThan(.14), reason: t.id);
      }
      // Rimessa sulla linea laterale sinistra, nella loro metà campo.
      final ti = board(SetPieceTemplate.rimessa).ball!;
      expect((ti.x < .02, ti.y < .5), (true, true));
      // Rinvio nella nostra area piccola (larga 0,215, profonda 0,047).
      final gk = board(SetPieceTemplate.rinvio).ball!;
      expect((gk.x - .5).abs(), lessThan(.108));
      expect(gk.y, greaterThan(1 - .047));
      // Calcio d'inizio: tutti nella nostra metà, la punta sul pallone.
      final ko = board(SetPieceTemplate.inizio);
      expect((ko.ball!.x, ko.ball!.y), (.5, .5));
      for (final t in ko.tokens) {
        expect(t.y, greaterThanOrEqualTo(.5), reason: t.id);
      }
      expect(_spotToken(ko, 1).id, 'f9', reason: 'la punta del 4-3-3');
      // Angolo contro: la nostra bandierina in basso, il portiere tra i pali (con il
      // nome nella lavagna), la zona attorno alla nostra area e una punta su.
      final ac = board(SetPieceTemplate.angoloContro);
      expect((ac.ball!.x < .05, ac.ball!.y > .97), (true, true));
      expect(_spotToken(ac, 0).y, inInclusiveRange(.9, .94));
      expect(
        ac.tokens.where((t) => t.y > 1 - .14 && (t.x - .5).abs() < .237),
        hasLength(3),
        reason: 'in area: il portiere e due ai lati dell\'area piccola',
      );
      expect(
        ac.tokens.where((t) => t.y > .75),
        hasLength(9),
        reason: 'la zona attorno all\'area',
      );
      expect(ac.tokens.where((t) => t.y < .65), hasLength(1));
    },
  );

  test('schemi da palla inattiva: chi batte viene dalla formazione pubblicata', () {
    BoardToken taker(SetPieceTemplate t, Formation? f) =>
        _spotToken(setPieceBoard(t, Team.milanac, _rosa, f), 1);

    // Angoli da sinistra e punizioni al Demo, angoli da destra e rigori a Rossi.
    for (final (t, id, name) in [
      (SetPieceTemplate.angoloSinistra, 'demo', 'Demo Direttivo'),
      (SetPieceTemplate.angoloDestra, 'p2', 'Marco Rossi'),
      (SetPieceTemplate.punizione, 'demo', 'Demo Direttivo'),
      (SetPieceTemplate.rigore, 'p2', 'Marco Rossi'),
    ]) {
      final tok = taker(t, _formation());
      expect((tok.playerId, tok.name), (id, name), reason: t.label);
    }
    final corner = setPieceBoard(
      SetPieceTemplate.angoloSinistra,
      Team.milanac,
      _rosa,
      _formation(),
    );
    final demo = corner.tokens.singleWhere((t) => t.playerId == 'demo');
    expect((demo.id, demo.label), ('f6', '10'));
    expect(demo.x, lessThan(.1), reason: 'sulla bandierina');
    // Gli altri giocatori della formazione ci sono, con nome e numero.
    expect(corner.tokens.singleWhere((t) => t.playerId == 'p4').id, 'f0');
    expect(
      corner.tokens.singleWhere((t) => t.playerId == 'p3').name,
      'Luca Bianchi',
    );
    // Dove manca il giocatore resta la sigla del ruolo.
    expect(corner.tokens.singleWhere((t) => t.id == 'f1').label, 'TS');

    // Non ancora pubblicata: i nomi dalla bozza, chi batte lo sceglie il ruolo.
    final draft = taker(
      SetPieceTemplate.angoloSinistra,
      _formation(published: false),
    );
    expect((draft.id, draft.label, draft.playerId), ('f5', 'CC', null));
    // Senza formazione: le sigle del 4-3-3.
    final none = setPieceBoard(
      SetPieceTemplate.rigore,
      Team.futuro,
      const [],
      null,
    );
    expect({for (final t in none.tokens) t.label}, containsAll(['POR', 'ATT']));
    expect(none.team, 'futuro');
    expect(none.tokens.every((t) => t.side == 'futuro'), isTrue);
    // Un battitore pubblicato che non è più tra i titolari non si usa.
    final gone = _formation().copyWith(
      publishedSetPieces: {SetPiece.rigori: 'p9'},
    );
    expect(taker(SetPieceTemplate.rigore, gone).id, 'f9', reason: 'la punta');
    // Un altro modulo: si gioca con i suoi posti.
    final f352 = Formation(
      id: 'g',
      module: '3-5-2',
      players: const {0: 'p4', 9: 'p2'},
      publishedAt: DateTime(2026, 11, 4),
      publishedModule: '3-5-2',
      publishedPlayers: const {0: 'p4', 9: 'p2'},
      publishedSetPieces: const {SetPiece.rigori: 'p2'},
    );
    final pen = setPieceBoard(
      SetPieceTemplate.rigore,
      Team.milanac,
      _rosa,
      f352,
    );
    expect(_spotToken(pen, 1).playerId, 'p2');
    expect({
      for (final t in pen.tokens) t.label,
    }, containsAll(['ES', 'ED', 'COC']));
  });

  test('la punizione spostata: prima del primo pallone giocato le zone seguono '
      'il pallone, dopo no', () {
    final s = setPieceBoard(
      SetPieceTemplate.punizione,
      Team.milanac,
      _rosa,
      _formation(),
    );
    final e = BoardEditor(s)
      ..apply(const GrabBall())
      ..apply(const MoveBall(.8, .2))
      ..apply(const DropBall());
    expect((e.state.piece!.x, e.state.piece!.y), (.8, .2));
    var zones = deliveryZones(e.state);
    expect(zones[0].x, greaterThan(.5), reason: 'il primo palo a destra');
    expect(zones[4].x, closeTo(.66, 1e-9), reason: 'il corto verso il centro');
    expect(e.state.piece!.kind, 'punizione');
    // Dopo il cross la palla inattiva resta dov'era.
    e
      ..apply(KickBall(x: zones[1].x, y: zones[1].y, cross: true))
      ..apply(const GrabBall())
      ..apply(const MoveBall(.2, .2))
      ..apply(const DropBall());
    expect((e.state.piece!.x, e.state.piece!.y), (.8, .2));
    zones = deliveryZones(e.state);
    expect(zones[0].x, greaterThan(.5));
    // Annullato tutto, torna il punto di partenza.
    for (var i = 0; i < 3; i++) {
      e.apply(const Undo());
    }
    expect((e.state.piece!.x, e.state.piece!.y), (.5, .24));
    e.dispose();
  });

  test('zone di battuta: dal lato del pallone, nell\'area giusta', () {
    BoardState board(SetPieceTemplate t) =>
        setPieceBoard(t, Team.milanac, _rosa, null);
    List<DeliveryZone> zones(SetPieceTemplate t) => deliveryZones(board(t));

    final left = zones(SetPieceTemplate.angoloSinistra);
    expect([for (final z in left) z.n], [1, 2, 3, 4, 5]);
    expect(
      [for (final z in left) z.name],
      ['primo palo', 'dischetto', 'secondo palo', 'limite dell\'area', 'corto'],
    );
    // In alto, nella loro area (profonda 0,14, larga da 0,26 a 0,74); il limite
    // appena fuori; il primo palo dal lato del pallone.
    for (final z in left.take(3)) {
      expect(z.y, lessThan(.14));
      expect(z.x, inInclusiveRange(.26, .74));
    }
    expect(left[3].y, inInclusiveRange(.14, .2));
    expect(left[0].x, lessThan(.5));
    expect(left[2].x, greaterThan(.5));
    // Il corto vicino alla bandierina, fuori dall'area.
    expect(left[4].x, lessThan(.26));
    expect(left[4].y, lessThan(.1));

    // Da destra: specchiate.
    final right = zones(SetPieceTemplate.angoloDestra);
    for (final (a, b) in [for (var i = 0; i < 5; i++) (left[i], right[i])]) {
      expect(b.x, closeTo(1 - a.x, 1e-9));
      expect(b.y, closeTo(a.y, 1e-9));
    }
    // Angolo contro: nella nostra area, in basso.
    final against = zones(SetPieceTemplate.angoloContro);
    for (final z in against.take(4)) {
      expect(z.y, greaterThan(.8));
    }
    expect(against[0].x, lessThan(.5));
    // Punizione centrale: il corto accanto al pallone.
    final fk = zones(SetPieceTemplate.punizione);
    expect((fk[4].y - .24).abs(), lessThan(.06));
    expect((fk[4].x - .5).abs(), inInclusiveRange(.08, .2));
    // Le zone non si accavallano (tranne che nello spazio del margine).
    for (final a in left) {
      for (final b in left) {
        if (a.n >= b.n) continue;
        final overlapX = (a.x - b.x).abs() < (a.w + b.w) / 2;
        final overlapY = (a.y - b.y).abs() < (a.h + b.h) / 2;
        expect(overlapX && overlapY, isFalse, reason: '${a.n} e ${b.n}');
      }
    }
    // Il tocco: la zona sotto il dito, o nessuna.
    final s = board(SetPieceTemplate.angoloSinistra);
    for (final z in left) {
      expect(deliveryZoneAt(s, z.x, z.y)?.n, z.n);
    }
    expect(deliveryZoneAt(s, .5, .6), isNull);
    // La legenda va a capo solo tra una zona e l'altra: dentro "2 dischetto" gli
    // spazi non si spezzano.
    expect(
      deliveryZoneLegend,
      startsWith('1\u00a0primo\u00a0palo · 2\u00a0dischetto'),
    );
    final pairs = deliveryZoneLegend.split(' · ');
    expect(pairs, hasLength(5));
    for (final pair in pairs) {
      expect(pair, isNot(contains(' ')), reason: pair);
    }
    expect(pairs[3], '4\u00a0limite\u00a0dell\'area');
    // Senza palla inattiva: la loro area, primo palo a sinistra.
    final plain = deliveryZones(const BoardState());
    expect(plain[0].x, lessThan(.5));
    expect(plain[1].y, lessThan(.14));
  });

  test('il cross: linea a puntini numerata come le altre, pallone libero nella '
      'zona, uguale nel replay', () {
    final s = setPieceBoard(
      SetPieceTemplate.angoloSinistra,
      Team.milanac,
      _rosa,
      _formation(),
    );
    final z2 = deliveryZones(s)[1];
    var now = 0;
    final editor = BoardEditor(s);
    final recorder = editor.startRecording(clock: () => now);
    final live = <int, String>{};
    void act(BoardCommand c) {
      now += 300;
      editor.apply(c);
      live[now] = _json(editor.state);
    }

    act(KickBall(x: z2.x, y: z2.y, cross: true));
    var line = editor.state.lines.single;
    expect((line.kind, line.n), (BallLineKind.cross, 1));
    expect(
      (line.x1, line.y1),
      (s.ball!.x, s.ball!.y),
      reason: 'dalla bandierina',
    );
    expect((line.x2, line.y2), (z2.x, z2.y));
    expect((line.fromPlayer, line.toPlayer), (false, false));
    final ball = editor.state.ball!;
    expect((ball.x, ball.y, ball.holder), (z2.x, z2.y, null));
    expect(editor.lastKick!.line, 1, reason: 'il volo del cross');
    // Il cross su un compagno arriva a lui: la palla gli va al piede, la linea
    // (sempre a puntini) finisce sul gettone.
    act(const Undo());
    final f9 = editor.state.tokenById('f9')!;
    act(KickBall(x: f9.x, y: f9.y, cross: true, to: 'f9'));
    expect(editor.state.ball!.holder, 'f9');
    line = editor.state.lines.single;
    expect((line.kind, line.toPlayer), (BallLineKind.cross, true));
    expect((line.x2, line.y2), (f9.x, f9.y));
    expect(
      (
        const KickBall(x: .5, y: .1, cross: true).version,
        KickBall(x: f9.x, y: f9.y, cross: true, to: 'f9').version,
      ),
      (2, 4),
      reason: 'una versione che non lo conosce lo rifarebbe libero nella zona',
    );
    // Poi un passaggio e un altro cross: la numerazione continua.
    act(const KickBall(x: .5, y: .2, to: 'f7'));
    act(
      KickBall(x: deliveryZones(s)[0].x, y: deliveryZones(s)[0].y, cross: true),
    );
    expect(
      [for (final l in editor.state.lines) l.kind],
      [BallLineKind.cross, BallLineKind.pass, BallLineKind.cross],
    );
    expect([for (final l in editor.state.lines) l.n], [1, 2, 3]);
    // Il cross parte dal piede di chi ce l'ha.
    line = editor.state.lines.last;
    expect(line.fromPlayer, isTrue);

    // JSON: il cross si chiama "x" (e il comando "cr").
    final json = BoardState.fromJson(
      (jsonDecode(_json(editor.state)) as Map).cast<String, dynamic>(),
    );
    expect(_json(json), _json(editor.state));
    expect(const KickBall(x: .5, y: .1, cross: true).toJson(), {
      'k': 'kick',
      'x': .5,
      'y': .1,
      'cr': true,
    });
    final back =
        BoardCommand.fromJson(
              const KickBall(x: .5, y: .1, cross: true).toJson(),
            )!
            as KickBall;
    expect((back.cross, back.shot), (true, false));
    // Una versione che non conosce i cross salta la linea (non lo schema).
    final old = BoardState.fromJson({
      ...editor.state.toJson(),
      'lines': [
        {'k': 'x', 'n': 1, 'x1': 0, 'y1': 0, 'x2': .5, 'y2': .1},
        {'k': 'q', 'n': 2, 'x1': 0, 'y1': 0, 'x2': .5, 'y2': .1},
      ],
    });
    expect(old.lines.single.kind, BallLineKind.cross);

    // Il replay rifà tutto uguale, a ogni istante.
    final data = ReplayData.fromBytes(recorder.finish(now + 500).toBytes());
    expect(data.version, 4, reason: 'c\'è un cross su un compagno');
    expect(_json(data.finalState), _json(editor.state));
    for (final MapEntry(key: t, value: state) in live.entries) {
      expect(_json(data.stateAt(t)), state, reason: 'a $t ms');
    }
    expect(_json(data.initial), _json(s), reason: 'parte dallo schema');
    editor.dispose();
  });

  test(
    'il disegno con zone, cross, fuorigioco e linee di reparto non si rompe',
    () async {
      final s = setPieceBoard(
        SetPieceTemplate.angoloSinistra,
        Team.milanac,
        _rosa,
        _formation(),
      );
      final editor =
          BoardEditor(
              s.copyWith(
                tokens: [
                  ...s.tokens,
                  const BoardToken(id: 'a1', x: .5, y: .01, side: 'avversari'),
                  const BoardToken(id: 'a2', x: .45, y: .08, side: 'avversari'),
                ],
              ),
            )
            ..apply(const KickBall(x: .5, y: .105, cross: true))
            ..apply(const SetView('fg', true))
            ..apply(const SetView('lr', true))
            ..apply(const SetView('pz', true))
            ..apply(SaveZone(ballZoneAt(.5, .105)));
      for (final width in [210.0, 900.0]) {
        final png = await renderBoardImage(editor.state, width: width);
        expect(png.length, greaterThan(1000));
      }
      editor.dispose();
    },
  );

  for (final (width, height) in [(360.0, 780.0), (320.0, 640.0)]) {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.dark ? 'scuro' : 'chiaro';
      testWidgets(
        'Palle inattive a ${width.toInt()} dp, tema $theme: angolo dal foglio del '
        'modulo, zone, cross, passaggio, annulla, salva in "Piazzati"',
        (tester) async {
          final formations = DemoFormationRepository();
          await formations.publish(await formations.loadCurrent(Team.milanac));
          await _openBoard(
            tester,
            width: width,
            height: height,
            brightness: brightness,
            formations: formations,
          );
          final before = _json(_live(tester));
          await _pickTemplate(tester, 'Angolo da sinistra');
          expect(tester.takeException(), isNull);
          var s = _live(tester);
          expect(s.piece!.kind, 'angolo_sx');
          expect(s.tokens, hasLength(11));
          expect(s.ball!.x, lessThan(.05));
          expect(s.shows(BoardOverlay.zones), isTrue);
          expect(find.text(setPieceModule), findsOneWidget, reason: 'in alto');
          // Il battitore della formazione pubblicata (il Demo) sulla bandierina.
          expect(s.tokenById('f6')!.x, lessThan(.1));

          // Con "Pallone" il suggerimento dà la legenda delle zone.
          await tester.tap(find.text('Pallone'));
          await tester.pumpAndSettle();
          expect(find.textContaining('1\u00a0primo\u00a0palo'), findsOneWidget);
          expect(find.textContaining('5\u00a0corto'), findsOneWidget);

          // Un tocco sulla zona 4 (lontano dai gettoni): cross, a puntini, e la
          // palla libera nel punto toccato.
          final z4 = deliveryZones(s)[3];
          await _tapField(tester, z4.x + .06, z4.y - .005);
          await tester.pump(const Duration(milliseconds: 100));
          expect(_canvas(tester).flight?.value, isNotNull, reason: 'in volo');
          await tester.pumpAndSettle();
          s = _live(tester);
          expect(s.lines.single.kind, BallLineKind.cross);
          expect(s.ball!.holder, isNull);
          expect(s.ball!.x, closeTo(z4.x + .06, .003));
          expect(s.ball!.y, closeTo(z4.y - .005, .003));

          // Chi blocca il portiere sta sul bordo della zona del primo palo: il
          // tocco su di lui è un cross che arriva a lui (non un passaggio).
          final screen = _spotToken(s, 5);
          expect(
            deliveryZoneAt(s, screen.x, screen.y, slackX: .02, slackY: .02),
            isNotNull,
          );
          await _tapField(tester, screen.x, screen.y);
          await tester.pumpAndSettle();
          s = _live(tester);
          expect(s.lines.last.kind, BallLineKind.cross);
          expect(s.lines.last.toPlayer, isTrue);
          expect(s.ball!.holder, screen.id);
          expect([for (final l in s.lines) l.n], [1, 2]);

          // Fuori dalle zone, un compagno: passaggio.
          final edge = _spotToken(s, 7);
          expect(deliveryZoneAt(s, edge.x, edge.y), isNull);
          await _tapField(tester, edge.x, edge.y);
          await tester.pumpAndSettle();
          s = _live(tester);
          expect(s.lines.last.kind, BallLineKind.pass);
          expect(s.ball!.holder, edge.id);
          expect([for (final l in s.lines) l.n], [1, 2, 3]);

          // Si salva in "Piazzati" (già scelto).
          await tester.tap(find.text('Salva'));
          await tester.pumpAndSettle();
          expect(find.text('Salva lo schema'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(DropdownButtonFormField<String>),
              matching: find.text(setPieceModule),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Annulla').last);
          await tester.pumpAndSettle();

          // Annulla: via il passaggio, i due cross e poi lo schema.
          for (var i = 0; i < 4; i++) {
            await tester.tap(find.text('Annulla'));
            await tester.pumpAndSettle();
          }
          expect(_json(_live(tester)), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Palle inattive: tutti gli schemi dal foglio, "Angolo contro" nella nostra '
    'area, registrato nel replay',
    (tester) async {
      await _openBoard(tester, width: 320, height: 640);
      // Il foglio a 320 dp: tutte le pillole si vedono intere.
      await tester.tap(find.byTooltip('Nuova lavagna dal modulo').first);
      await tester.pumpAndSettle();
      for (final t in SetPieceTemplate.values) {
        await tester.ensureVisible(find.text(t.label));
        expect(find.text(t.label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Registra il replay'));
      await tester.pump();
      for (final t in SetPieceTemplate.values) {
        await _pickTemplate(tester, t.label);
        final s = _live(tester);
        expect(s.piece!.kind, t.key);
        expect((s.ball!.x, s.ball!.y), t.spot);
      }
      // L'ultimo è "Angolo contro": la palla è da noi, il pallino della scelta
      // nel foglio è su di lui.
      await tester.tap(find.byTooltip('Nuova lavagna dal modulo').first);
      await tester.pumpAndSettle();
      final pill = tester.widget<FilterPill>(
        find.widgetWithText(FilterPill, 'Angolo contro'),
      );
      expect(pill.selected, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ferma la registrazione'));
      await tester.pumpAndSettle();
      final data = tester
          .widget<ReplayPreviewPage>(find.byType(ReplayPreviewPage))
          .data;
      expect(
        data.events.where((e) => e.command is Reset),
        hasLength(SetPieceTemplate.values.length),
      );
      expect(data.finalState.piece!.kind, 'angolo_contro');
      expect(tester.takeException(), isNull);
    },
  );
}
