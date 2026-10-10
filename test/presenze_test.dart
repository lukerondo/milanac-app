import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/presenze/attendance.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayAt;

Future<void> openPresenze(WidgetTester tester, DateTime now) async {
  await startAppAt(tester, now);
  await goToSection(tester, 'Presenze');
}

/// Scorre la lista del giorno fino a [finder] (in su con [delta] negativo).
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 150,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('presenze-giorno')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('statistiche: il ritardo conta come presenza, l\'assenza automatica '
      'come assenza', () {
    final d = DateTime(2026, 10, 1);
    final stats = AttendanceStats([
      AttendanceEntry(
        playerId: 'x',
        date: d,
        status: AttendanceStatus.presente,
      ),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.ritardo),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.assente),
      AttendanceEntry(
        playerId: 'x',
        date: d,
        status: AttendanceStatus.assente,
        auto: true,
      ),
    ]);
    expect(stats.percent, 50);
    expect(stats.late, 1);
    expect(stats.absent, 2);
    expect(stats.autoAbsent, 1);
  });

  testWidgets('calendario: la serata di oggi, gli elenchi e la risposta', (
    tester,
  ) async {
    await openPresenze(tester, todayAt(17));
    expect(find.textContaining('STASERA ·'), findsOneWidget);
    expect(find.text('Allenamento alle 21:30'), findsOneWidget);
    expect(find.text('Ci sei? Rispondi entro le 18:30.'), findsOneWidget);
    await scrollTo(tester, find.text('SENZA RISPOSTA (3)'));
    await scrollTo(
      tester,
      find.text('In ritardo, arrivo alle 21:50 · Esco tardi da lavoro'),
    );

    await scrollTo(
      tester,
      find.widgetWithText(OutlinedButton, 'Presente'),
      delta: -150,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente').first);
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Presente'), findsOneWidget);
    await scrollTo(tester, find.text('SENZA RISPOSTA (2)'));
    await scrollTo(tester, find.text('PRESENTI (1)'));
  });

  testWidgets('ritardo con nota obbligatoria; assenza e storico', (
    tester,
  ) async {
    await openPresenze(tester, todayAt(17));

    await scrollTo(tester, find.widgetWithText(OutlinedButton, 'In ritardo'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'In ritardo').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // orario proposto: 22:00
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.text('Scrivi il motivo del ritardo.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Lavoro');
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(
      find.text('La tua risposta: In ritardo, arrivo alle 22:00 · Lavoro'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Assente').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Febbre');
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Assente · Febbre'), findsOneWidget);

    // Lo storico di Marco Rossi, con i pulsanti del Direttivo.
    await scrollTo(tester, find.text('Marco Rossi'));
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Storico presenze'), findsOneWidget);
    expect(find.textContaining('Segna per questo giocatore'), findsOneWidget);
  });

  testWidgets('dopo le 18:30 i pulsanti sono spenti', (tester) async {
    await openPresenze(tester, todayAt(18, 31));
    await scrollTo(tester, find.textContaining('Risposte chiuse alle 18:30'));
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Presente').first,
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Statistiche'));
    await tester.pumpAndSettle();
    expect(find.textContaining('puntuale'), findsWidgets);
  });
}
