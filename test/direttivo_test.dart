import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/direttivo/direttivo_page.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayAt;

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Sala Direttivo: avviso in Comunicazioni e chat riservata', (
    tester,
  ) async {
    await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'Sala Direttivo');
    expect(find.text('senza risposta stasera'), findsOneWidget);
    expect(find.text('video proposto'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Avviso a tutti'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avviso a tutti'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Stasera si gioca alle 22');
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();
    expect(
      find.text('Avviso inviato in Comunicazioni a tutto il club.'),
      findsOneWidget,
    );

    await goToSection(tester, 'Chat');
    // Il canale riservato compare (la demo è Direttivo), con il lucchetto.
    expect(find.text('Sala Direttivo'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    await tester.tap(find.text('Comunicazioni'));
    await tester.pumpAndSettle();
    expect(find.text('AVVISO DEL DIRETTIVO'), findsOneWidget);
    expect(find.text('Stasera si gioca alle 22'), findsOneWidget);
  });

  testWidgets('Presenze di stasera: il Direttivo corregge anche dopo le 18:30', (
    tester,
  ) async {
    await startAppAt(tester, todayAt(18, 31));
    await goToSection(tester, 'Sala Direttivo');
    await tester.tap(find.text('Presenze di stasera'));
    await tester.pumpAndSettle();
    expect(find.text('PRESENZE DI STASERA'), findsOneWidget);
    expect(find.textContaining('risposte chiuse alle 18:30'), findsOneWidget);
    expect(find.text('SENZA RISPOSTA (4)'), findsOneWidget);

    await tester.tap(find.text('Luca Bianchi'));
    await tester.pumpAndSettle();
    expect(find.text('Segna per lui (Direttivo):'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente'));
    await tester.pumpAndSettle();
    expect(find.text('SENZA RISPOSTA (3)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Presente · segnata dal Direttivo'),
      100,
      scrollable: find.descendant(
        of: find.byType(TonightAttendancePage),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Presente · segnata dal Direttivo'), findsOneWidget);
  });

  testWidgets('Rosa e squadre: i membri rimossi si vedono e si riattivano', (
    tester,
  ) async {
    await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'Sala Direttivo');
    await tester.scrollUntilVisible(
      find.text('Rosa e squadre'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Rosa e squadre'));
    await tester.pumpAndSettle();
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('RIMOSSI'), 300, scrollable: page);
    expect(find.text('Gigi Ferri'), findsOneWidget);
    await tester.ensureVisible(find.text('Riattiva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riattiva'));
    await tester.pumpAndSettle();
    expect(find.text('RIMOSSI'), findsNothing);
    expect(find.text('Gigi Ferri è di nuovo nella rosa.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'Tutte (6)'),
      -300,
      scrollable: page,
    );
    expect(find.widgetWithText(ChoiceChip, 'Tutte (6)'), findsOneWidget);
  });
}
