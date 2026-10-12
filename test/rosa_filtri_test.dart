import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/rosa/rosa_page.dart';
import 'package:milanac/shared/ui.dart';

import 'helpers.dart';

import 'home_test.dart';
import 'rosa_view.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Rosa: mini carte, ricerca e filtri per squadra e reparto', (
    tester,
  ) async {
    await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'Rosa completa');

    // Vista predefinita: le mini carte di tutti (ordinate per overall).
    expect(find.text('MARCO ROSSI'), findsOneWidget);
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('PAOLO VERDI'), findsOneWidget);
    // Chi ha la carta speciale la mostra anche in miniatura.
    expect(find.text('91'), findsOneWidget); // Rossi 86 + 5
    expect(find.text('75'), findsOneWidget); // Neri 70 + 5 (blu)
    expect(find.text('NERO/ORO'), findsNWidgets(3));
    expect(find.text('BLU ELETTRICO'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tocca una carta per aprire il profilo del giocatore.'),
      100,
      scrollable: find.byType(Scrollable).at(1),
    );

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
    await tester.tap(find.widgetWithText(FilterPill, 'POR'));
    await tester.pumpAndSettle();
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    await tester.tap(find.widgetWithText(FilterPill, 'Tutti'));
    await tester.pumpAndSettle();

    // Squadra: il Futuro ha Neri e Verdi.
    await tester.tap(find.widgetWithText(FilterPill, 'Futuro · 2'));
    await tester.pumpAndSettle();
    expect(find.text('ANDREA NERI'), findsOneWidget);
    expect(find.text('PAOLO VERDI'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    await tester.tap(find.widgetWithText(FilterPill, 'Tutte · 5'));
    await tester.pumpAndSettle();

    // Nessun risultato.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nessun membro corrisponde ai filtri.'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancella'));
    await tester.pumpAndSettle();

    // Elenco classico, diviso tra Direttivo e giocatori.
    await showRosaAs(tester, RosaView.elenco);
    expect(find.text('Marco Rossi'), findsOneWidget);
    expect(find.text('MARCO ROSSI'), findsNothing);
    expect(find.text('DIRETTIVO'), findsOneWidget);
    expect(find.text('GIOCATORI'), findsOneWidget);

    // La mini carta apre la carta del giocatore.
    await showRosaAs(tester, RosaView.carte);
    await tester.ensureVisible(find.text('ANDREA NERI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ANDREA NERI'));
    await tester.pumpAndSettle();
    expect(find.text('CARTA GIOCATORE'), findsOneWidget);
    expect(find.textContaining('Blu elettrico · scade'), findsOneWidget);
  });

  testWidgets('Rosa: il pulsante della barra in alto passa all\'elenco e '
      'torna alle carte', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            appBar: AppBar(actions: const [RosaViewButton()]),
            body: Consumer(
              builder: (_, ref, _) => Text(ref.watch(rosaViewProvider).name),
            ),
          ),
        ),
      ),
    );
    expect(find.text('carte'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostra come elenco'));
    await tester.pump();
    expect(find.text('elenco'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostra come carte'));
    await tester.pump();
    expect(find.text('carte'), findsOneWidget);
  });
}
