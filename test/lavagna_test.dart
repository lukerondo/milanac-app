import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/audio_focus.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/chat/chat_repository.dart' show maxVoiceSeconds;
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/lavagna/board_page.dart';
import 'package:milanac/features/lavagna/board_painter.dart';
import 'package:milanac/features/lavagna/replay_pages.dart';
import 'package:milanac/features/lavagna/replay_player.dart';
import 'package:milanac/features/tattiche/tactics_repository.dart';

import 'helpers.dart';

import 'home_test.dart';

/// Il microfono finto della registrazione del replay (niente file audio: replay
/// senza voce). Con [opening] si apre solo quando lo si completa.
class _FakeMic implements VoiceRecorder {
  Completer<bool>? opening;
  int starts = 0, stops = 0, cancels = 0;
  bool _on = false;

  @override
  bool get isRecording => _on;

  @override
  Future<bool> start() async {
    starts++;
    _on = await (opening?.future ?? Future.value(true));
    return _on;
  }

  @override
  Future<({Uint8List bytes, int seconds, String path})?> stop({
    int maxSeconds = maxVoiceSeconds,
    bool keepFile = false,
  }) async {
    stops++;
    _on = false;
    return null;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _on = false;
  }

  @override
  void dispose() {}
}

/// Una pagina con il pulsante "apri" che porta a [page] (così si può tornare indietro).
Future<ProviderContainer> _openPage(
  WidgetTester tester,
  Widget Function() page, {
  _FakeMic? mic,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [if (mic != null) replayMicProvider.overrideWithValue(() => mic)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  c,
                ).push(MaterialPageRoute(builder: (_) => page())),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
  return container;
}

/// La lavagna viva (anche sotto l'anteprima del replay).
BoardState _live(WidgetTester tester) => tester
    .widget<BoardCanvas>(
      find.byKey(const ValueKey('lavagna'), skipOffstage: false),
    )
    .board
    .value;

String _json(BoardState s) => jsonEncode(s.toJson());

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('lavagna: azioni, annulla, salvataggio in JSON e replay nel tempo', () {
    final editor = BoardEditor();
    final recorded = <BoardCommand>[];
    editor.onCommand = recorded.add;
    editor.apply(
      const AddToken(BoardToken(id: 'a', x: .5, y: .5, label: '9', name: 'Rossi')),
    );
    editor.apply(const DragStart('a'));
    editor.apply(const MoveToken('a', .6, .4));
    editor.apply(const MoveToken('a', .7, .3));
    editor.apply(const DragEnd());
    expect(editor.state.tokenById('a')!.x, .7);
    editor.apply(const Undo());
    expect(editor.state.tokenById('a')!.x, .5, reason: 'annulla tutto il trascinamento');
    editor.apply(const HeatStart());
    editor.apply(const Heat(.2, .2));
    editor.apply(const Heat(.21, .22));
    editor.apply(const HeatEnd());
    editor.apply(const AddArrow(BoardArrow(x1: .1, y1: .1, x2: .4, y2: .4, dashed: true)));
    expect(editor.state.heat, hasLength(2));
    expect(editor.state.arrows.single.dashed, isTrue);
    expect(recorded, hasLength(11));

    // Andata e ritorno dal JSON.
    final json = editor.state.toJson();
    final back = BoardState.fromJson(json);
    expect(back.tokens.single.name, 'Rossi');
    expect(back.arrows.single.x2, .4);
    expect(back.heat.first.x, .2);
    expect(back.toPreviewJson()['heat'], isEmpty);

    // Il replay rifà le stesse mosse fino a un istante.
    final data = ReplayData(
      initial: const BoardState(),
      durationMs: 5000,
      events: [
        for (final (i, c) in recorded.indexed) ReplayEvent(i * 400, c),
      ],
    );
    expect(data.stateAt(0).tokens, hasLength(1));
    expect(data.stateAt(1300).tokenById('a')!.x, .7); // dopo il trascinamento
    expect(data.stateAt(2000).tokenById('a')!.x, .5); // dopo l'annulla
    expect(data.stateAt(5000).arrows, hasLength(1));
    final bytes = data.toBytes();
    final again = ReplayData.fromBytes(bytes);
    expect(again.events, hasLength(11));
    expect(again.finalState.heat, hasLength(2));
    expect(bytes.length, lessThan(2000), reason: 'pochi KB');

    // Pulisci e carica.
    editor.apply(const Clear());
    expect(editor.state.isEmpty, isTrue);
    editor.load(demoBoard());
    expect(editor.canUndo, isFalse);
    expect(editor.state.tokens, hasLength(12));
    expect(demoReplay().finalState.arrows, hasLength(2));
  });

  testWidgets('Lavagna: gettoni, freccia, fuoco, annulla, salvataggio e replay in chat', (
    tester,
  ) async {
    final container = await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'Tattiche & Build');
    expect(find.text('Uscita dal basso'), findsOneWidget); // schema demo con lavagna
    await tester.tap(find.text('Lavagna'));
    await tester.pumpAndSettle();
    expect(find.text('LAVAGNA'), findsOneWidget);
    final board = find.byKey(const ValueKey('lavagna'));
    expect(board, findsOneWidget);

    // Giocatore: un tocco in un punto libero apre la scelta; aggiungiamo un avversario.
    final rect = tester.getRect(board);
    await tester.tapAt(rect.topLeft + Offset(rect.width * .5, rect.height * .36));
    await tester.pumpAndSettle();
    expect(find.text('Avversario'), findsOneWidget);
    await tester.tap(find.text('Avversario'));
    await tester.pumpAndSettle();

    // Freccia: trascinando compare una freccia; Annulla la toglie.
    await tester.tap(find.text('Freccia'));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      rect.topLeft + Offset(rect.width * .3, rect.height * .5),
      Offset(0, -rect.height * .2),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuoco'));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      rect.topLeft + Offset(rect.width * .8, rect.height * .5),
      Offset(0, rect.height * .15),
    );
    await tester.pumpAndSettle();

    // Salva: lo schema compare in Tattiche e schemi con la lavagna.
    await tester.tap(find.byTooltip('Salva lo schema'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Prova lavagna');
    await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
    // L'immagine dello schema si disegna davvero (serve il tempo reale).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prova lavagna'), findsOneWidget);
    final saved = container
        .read(tacticsProvider)
        .value!
        .firstWhere((t) => t.title == 'Prova lavagna');
    expect(saved.board!.tokens, hasLength(12)); // 11 del modulo + l'avversario
    expect(saved.board!.tokens.where((t) => t.side == 'avversari'), hasLength(1));
    expect(saved.board!.arrows, hasLength(1));
    expect(saved.board!.heat, isNotEmpty);
    expect(saved.localImage, isNotNull); // immagine esportata

    // Riaperto, si può annullare... no: la cronologia riparte; ma la freccia c'è.
    await tester.tap(find.text('Prova lavagna'));
    await tester.pumpAndSettle();
    expect(find.text('Apri la lavagna'), findsOneWidget);
    await tester.tap(find.text('Apri la lavagna'));
    await tester.pumpAndSettle();
    expect(find.text('PROVA LAVAGNA'), findsOneWidget);
    await tester.tap(find.text('Freccia'));
    await tester.pumpAndSettle();
    final rect2 = tester.getRect(find.byKey(const ValueKey('lavagna')));
    await tester.dragFrom(
      rect2.topLeft + Offset(rect2.width * .6, rect2.height * .6),
      Offset(rect2.width * .2, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Il replay in chat: riquadro con Play, poi la riproduzione (senza audio in demo).
    await goToSection(tester, 'Chat');
    await tester.tap(find.text('Tattiche & Schemi'));
    await tester.pumpAndSettle();
    expect(find.text('SCHEMA CON AUDIO'), findsOneWidget);
    expect(find.text('Uscita dal basso'), findsOneWidget);
    await tester.tap(find.byTooltip('Riproduci il replay'));
    await tester.pumpAndSettle();
    expect(find.text('REPLAY DELLA LAVAGNA'), findsOneWidget);
    expect(find.text('Senza audio'), findsOneWidget);
    expect(find.text('0:00 / 0:20'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:02 / 0:20'), findsOneWidget);
    expect(container.read(audioFocusProvider), {AudioUse.replay});
    await tester.tap(find.byTooltip('Pausa'));
    await tester.pumpAndSettle();
    expect(container.read(audioFocusProvider), isEmpty);

    // Un altro prende l'audio (un vocale): il replay va in pausa.
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(seconds: 1));
    container.read(audioFocusProvider.notifier).claim(AudioUse.vocale);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('0:03 / 0:20'), findsOneWidget);
  });

  test('replay: durata in millisecondi, l\'ultima mossa si vede', () {
    var now = 0;
    final editor = BoardEditor(demoBoard());
    final rec = editor.startRecording(clock: () => now);
    now = 4200;
    editor
      ..apply(const DragStart('t9'))
      ..apply(const MoveToken('t9', .5, .3))
      ..apply(const DragEnd());
    now = 10300;
    editor.apply(const AddArrow(BoardArrow(x1: .5, y1: .3, x2: .5, y2: .1)));
    editor.onCommand = null;

    // La voce dura 10 s (prima la durata era in secondi interi e il replay si
    // fermava lì): il replay arriva fino all'ultima mossa, a 10,3 s.
    final data = rec.finish(10000);
    expect(data.durationMs, 10300);
    expect(data.finalState.arrows, hasLength(3));
    expect(_json(data.finalState), _json(editor.state));
    // Senza la durata della voce vale il tempo misurato, in millisecondi.
    now = 12345;
    expect(rec.finish().durationMs, 12345);
    // I replay già in chat con la durata arrotondata si allungano fino all'ultima mossa.
    final old = ReplayData.fromJson({...data.toJson(), 'ms': 10000});
    expect(old.durationMs, 10300);
    expect(old.finalState.arrows, hasLength(3));
  });

  testWidgets('replay senza voce: orologio senza ritardi, alla fine l\'ultima mossa', (
    tester,
  ) async {
    const data = ReplayData(
      initial: BoardState(),
      durationMs: 10300,
      events: [
        ReplayEvent(10300, AddArrow(BoardArrow(x1: .1, y1: .1, x2: .5, y2: .5))),
      ],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final player = ReplayPlayer(
      data,
      focus: container.read(audioFocusProvider.notifier),
    );
    addTearDown(player.dispose);

    await player.play();
    expect(container.read(audioFocusProvider), {AudioUse.replay});
    await tester.pump(const Duration(seconds: 5));
    expect(player.positionMs, 5000); // i passi si contano, non si sommano
    expect(player.state.arrows, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    expect(player.playing, isFalse);
    expect(player.positionMs, 10300);
    expect(player.state.arrows, hasLength(1));
    expect(container.read(audioFocusProvider), isEmpty);

    // Spostando la barra a fine replay non riparte da solo.
    await player.seek(2000);
    await tester.pump(const Duration(seconds: 1));
    expect(player.positionMs, 2000);
    expect(player.state.arrows, isEmpty);
  });

  test('Annulla durante la registrazione: nel replay come nel vivo', () {
    var now = 0;
    final editor = BoardEditor(demoBoard());
    // Una freccia disegnata prima di registrare.
    editor.apply(const AddArrow(BoardArrow(x1: .2, y1: .2, x2: .4, y2: .4)));
    expect(editor.canUndo, isTrue);
    final rec = editor.startRecording(clock: () => now);
    // La cronologia riparte da qui: il replay non conosce le mosse di prima.
    expect(editor.canUndo, isFalse);
    now = 1000;
    editor
      ..apply(const DragStart('t6'))
      ..apply(const MoveToken('t6', .5, .7))
      ..apply(const DragEnd());
    now = 2000;
    editor.apply(const Undo());
    expect(editor.state.tokenById('t6')!.y, .56);
    expect(editor.canUndo, isFalse);
    editor.onCommand = null;
    final data = rec.finish(3000);
    expect(data.initial.arrows, hasLength(3));
    expect(_json(data.finalState), _json(editor.state));
  });

  test('heatmap: diradata dove il colore è già pieno, con un limite', () {
    var s = const BoardState();
    for (var i = 0; i < 11; i++) {
      s = s.copyWith(heat: [...s.heat, const HeatPoint(.5, .5)]);
    }
    expect(s.heatSaturatedAt(.5, .5), isFalse);
    s = s.copyWith(heat: [...s.heat, const HeatPoint(.51, .51)]);
    expect(s.heatSaturatedAt(.5, .5), isTrue);
    expect(s.heatSaturatedAt(.6, .5), isFalse);
    expect(s.heatFull, isFalse);
    // Al limite lo schema resta molto sotto i 300 KB del database.
    final full = BoardState(
      tokens: demoBoard().tokens,
      heat: [
        for (var i = 0; i < BoardState.maxHeat; i++)
          HeatPoint((i % 997) / 997, (i % 991) / 991),
      ],
    );
    expect(full.heatFull, isTrue);
    expect(jsonEncode(full.toJson()).length, lessThan(100000));
  });

  testWidgets('Registra: il doppio tocco apre una sola registrazione, un solo contatore', (
    tester,
  ) async {
    final mic = _FakeMic()..opening = Completer<bool>();
    final container = await _openPage(tester, () => const BoardPage(), mic: mic);
    // Il microfono ci mette un po' ad aprirsi: intanto si tocca di nuovo.
    await tester.tap(find.byTooltip('Registra il replay'));
    await tester.pump();
    await tester.tap(find.byTooltip('Registra il replay'));
    await tester.pump();
    expect(container.read(audioFocusProvider), {AudioUse.registrazioneReplay});
    mic.opening!.complete(true);
    await tester.pump();
    expect(mic.starts, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('0:03'), findsOneWidget); // con due contatori sarebbe 0:06

    await tester.tap(find.byTooltip('Ferma la registrazione'));
    await tester.pumpAndSettle();
    expect(mic.stops, 1);
    expect(container.read(audioFocusProvider), isEmpty);
    expect(find.text('ANTEPRIMA DEL REPLAY'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('0:03'), findsNothing); // nessun contatore rimasto acceso

    // Indietro dall'anteprima: prima si chiede, il replay non inviato si perderebbe.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Eliminare il replay?'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(find.text('ANTEPRIMA DEL REPLAY'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('ANTEPRIMA DEL REPLAY'), findsNothing);
    expect(find.text('LAVAGNA'), findsOneWidget);
  });

  testWidgets('Annulla durante la registrazione: il replay finisce come la lavagna', (
    tester,
  ) async {
    final mic = _FakeMic();
    await _openPage(tester, () => const BoardPage(), mic: mic);
    final rect = tester.getRect(find.byKey(const ValueKey('lavagna')));
    Future<void> arrow(double x) async {
      await tester.dragFrom(
        rect.topLeft + Offset(rect.width * x, rect.height * .5),
        Offset(0, -rect.height * .2),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Freccia'));
    await tester.pumpAndSettle();
    await arrow(.3); // prima di registrare
    expect(_live(tester).arrows, hasLength(1));

    await tester.tap(find.byTooltip('Registra il replay'));
    await tester.pump();
    // "Annulla" non toglie la freccia di prima: nel replay c'è già dall'inizio e
    // l'annullamento non avrebbe niente da togliere.
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    expect(_live(tester).arrows, hasLength(1));
    await arrow(.6);
    expect(_live(tester).arrows, hasLength(2));
    await tester.tap(find.text('Annulla'));
    await tester.pump();
    expect(_live(tester).arrows, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Ferma la registrazione'));
    await tester.pumpAndSettle();

    final data = tester
        .widget<ReplayPreviewPage>(find.byType(ReplayPreviewPage))
        .data;
    expect(data.initial.arrows, hasLength(1));
    expect(_json(data.finalState), _json(_live(tester)));
  });

  testWidgets('Registrazione troppo breve e uscita a metà: la voce si butta', (
    tester,
  ) async {
    final mic = _FakeMic();
    final container = await _openPage(tester, () => const BoardPage(), mic: mic);
    await tester.tap(find.byTooltip('Registra il replay'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Ferma la registrazione'));
    await tester.pumpAndSettle();
    expect(find.text('Registrazione troppo breve.'), findsOneWidget);
    expect(mic.cancels, 1); // il file temporaneo non resta sul telefono
    expect(mic.stops, 0);
    expect(find.byType(ReplayPreviewPage), findsNothing);

    // Indietro durante la registrazione: prima si chiede.
    await tester.tap(find.byTooltip('Registra il replay'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Interrompere la registrazione?'), findsOneWidget);
    await tester.tap(find.text('Continua'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:03'), findsOneWidget); // registra ancora
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(find.text('apri'), findsOneWidget);
    expect(mic.cancels, 2);
    expect(container.read(audioFocusProvider), isEmpty);
  });

  testWidgets('Lavagna da un link vecchio: "Schema non trovato" e si torna indietro', (
    tester,
  ) async {
    await _openPage(tester, () => const SavedBoardPage(tacticId: 'non-esiste'));
    expect(find.text('Schema non trovato'), findsOneWidget);
    await tester.tap(find.text('Torna alle tattiche'));
    await tester.pumpAndSettle();
    expect(find.text('apri'), findsOneWidget);
  });
}
