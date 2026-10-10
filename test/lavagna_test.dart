import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/tattiche/tactics_repository.dart';

import 'carte_speciali_test.dart' show openSection;
import 'home_test.dart';

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
    await openSection(tester, 'Tattiche & Build');
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
    await openSection(tester, 'Chat');
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
    await tester.tap(find.byTooltip('Pausa'));
    await tester.pumpAndSettle();
  });
}
