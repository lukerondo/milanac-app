import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'carte_speciali_test.dart' show openSection;
import 'home_test.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Rosa: mini carte, ricerca e filtri per squadra, reparto e Direttivo', (
    tester,
  ) async {
    await startAppAt(tester, todayAt(17));
    await openSection(tester, 'Rosa completa');

    // Vista predefinita: le mini carte di tutti (ordinate per overall).
    expect(find.text('MARCO ROSSI'), findsOneWidget);
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('PAOLO VERDI'), findsOneWidget);
    // Chi ha la carta speciale la mostra anche in miniatura.
    expect(find.text('91'), findsOneWidget); // Rossi 86 + 5
    expect(find.text('75'), findsOneWidget); // Neri 70 + 5 (blu)

    // Ricerca per nome, cognome o gamertag.
    await tester.enterText(find.byType(TextField), 'neri');
    await tester.pumpAndSettle();
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    await tester.enterText(find.byType(TextField), 'diavolo');
    await tester.pumpAndSettle();
    expect(find.text('MARCO ROSSI'), findsOneWidget);
    expect(find.text('ANDREA NERI'), findsNothing);
    await tester.tap(find.byTooltip('Cancella'));
    await tester.pumpAndSettle();
    expect(find.text('ANDREA NERI'), findsOneWidget);

    // Reparto: solo i portieri.
    await tester.tap(find.widgetWithText(ChoiceChip, 'POR'));
    await tester.pumpAndSettle();
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tutti i reparti'));
    await tester.pumpAndSettle();

    // Squadra: il Futuro ha Neri e Verdi.
    await tester.tap(find.widgetWithText(ChoiceChip, 'FUTURO (2)'));
    await tester.pumpAndSettle();
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('PAOLO VERDI'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tutte (5)'));
    await tester.pumpAndSettle();

    // Solo il Direttivo.
    await tester.tap(find.widgetWithText(FilterChip, 'Solo Direttivo'));
    await tester.pumpAndSettle();
    expect(find.text('DEMO DIRETTIVO'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'Solo Direttivo'));
    await tester.pumpAndSettle();

    // Nessun risultato.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nessun membro corrisponde ai filtri.'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancella'));
    await tester.pumpAndSettle();

    // Elenco classico ancora disponibile.
    await tester.tap(find.text('Elenco'));
    await tester.pumpAndSettle();
    expect(find.text('Marco Rossi'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);

    // La mini carta apre la carta del giocatore.
    await tester.tap(find.text('Mini'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ANDREA NERI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ANDREA NERI'));
    await tester.pumpAndSettle();
    expect(find.text('CARTA GIOCATORE'), findsOneWidget);
    expect(find.text('BLU ELETTRICO'), findsOneWidget);
  });
}
