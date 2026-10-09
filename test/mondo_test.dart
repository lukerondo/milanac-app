import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<void> openMondo(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  await goToSection(tester, 'Mondo Proclub');
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Mondo Proclub: il Direttivo pubblica una proposta e aggiunge '
      'un video', (tester) async {
    await openMondo(tester);
    expect(find.text('La build da attaccante più forte'), findsOneWidget);
    expect(find.text('PROPOSTE DA APPROVARE (1)'), findsOneWidget);
    expect(find.textContaining('Proposto da Luca Bianchi'), findsOneWidget);

    await tester.tap(find.text('Pubblica'));
    await tester.pumpAndSettle();
    expect(find.text('PROPOSTE DA APPROVARE (1)'), findsNothing);
    // Ora è tra i video, filtrabile per ruolo.
    await tester.tap(find.widgetWithText(ChoiceChip, 'DC'));
    await tester.pumpAndSettle();
    expect(
      find.text('Difendere in 11 contro 11: i movimenti del DC'),
      findsOneWidget,
    );
    expect(find.text('La build da attaccante più forte'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tutti'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aggiungi video'));
    await tester.pumpAndSettle();
    expect(find.text('Nuovo video'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Calci piazzati: i migliori schemi',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'youtu.be/schemi123',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Calci piazzati: i migliori schemi'), findsOneWidget);
  });

  testWidgets('Mondo Proclub: le notizie con il filtro Console', (
    tester,
  ) async {
    await openMondo(tester);
    await tester.tap(find.text('Notizie'));
    await tester.pumpAndSettle();
    expect(find.text('Leggi la notizia'), findsWidgets);
    // I filtri scorrono in orizzontale: porta in vista "Console".
    await tester.drag(
      find.widgetWithText(ChoiceChip, 'Tutte'),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Console'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PS5: disponibile'), findsOneWidget);
    expect(find.textContaining('FVPA: aperte'), findsNothing);
  });
}
