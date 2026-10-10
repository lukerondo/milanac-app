import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('ogni modulo ha 11 posizioni, portiere per primo, dentro il campo', () {
    for (final entry in formationModules.entries) {
      expect(entry.value, hasLength(11), reason: entry.key);
      expect(entry.value.first.label, 'POR', reason: entry.key);
      for (final s in entry.value) {
        expect(s.x, inInclusiveRange(0, 1));
        expect(s.y, inInclusiveRange(0, 1));
      }
    }
  });

  test('assegnare un giocatore già in campo lo sposta', () {
    const f = Formation(players: {1: 'a', 2: 'b'});
    final next = f.assign(5, 'a');
    expect(next.players, {2: 'b', 5: 'a'});
    expect(next.assign(2, null).players, {5: 'a'});
  });

  testWidgets('Formazione: il Direttivo schiera un giocatore e cambia modulo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, 'Formazione');

    // I giocatori vedono solo la formazione pubblicata: per ora non c'è.
    expect(
      find.textContaining('non è ancora stata pubblicata'),
      findsOneWidget,
    );
    await tester.tap(find.text('Prepara e pubblica nella Sala Direttivo'));
    await tester.pumpAndSettle();
    expect(find.text('FORMAZIONI'), findsOneWidget);

    // In demo: Neri (POR), Bianchi, Demo, Rossi in campo. Nessuno in panchina.
    expect(find.text('Neri'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tutti i giocatori sono in campo.'),
      200,
    );
    expect(find.text('Tutti i giocatori sono in campo.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Neri'), -200);

    // Libera il portiere: Neri finisce in panchina.
    await tester.tap(find.text('Neri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libera la posizione'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Andrea Neri'),
      findsOneWidget,
    ); // chip in panchina

    // Cambio modulo: i giocatori restano schierati.
    await tester.scrollUntilVisible(find.text('3-5-2'), -200);
    await tester.tap(find.text('3-5-2'));
    await tester.pumpAndSettle();
    expect(find.text('Rossi'), findsOneWidget);

    // Pubblicazione: conferma, poi lo stato diventa "Pubblicata oggi".
    await tester.scrollUntilVisible(find.textContaining('Bozza'), -200);
    expect(find.textContaining('Bozza'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pubblica la formazione di stasera'),
      200,
    );
    await tester.ensureVisible(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pubblica'));
    await tester.pumpAndSettle();
    expect(find.text('Ripubblica e avvisa i giocatori'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Pubblicata oggi'),
      -200,
    );
    expect(find.textContaining('Pubblicata oggi'), findsOneWidget);

    // Tornando alla sezione Formazione: la versione pubblicata (3-5-2, Neri in panchina).
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.textContaining('non è ancora stata pubblicata'), findsNothing);
    expect(find.widgetWithText(Chip, '3-5-2'), findsOneWidget);
    expect(find.text('Rossi'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Andrea Neri'), 200);
    expect(find.textContaining('Andrea Neri'), findsOneWidget);
  });

  testWidgets('Sala Direttivo: una formazione per squadra', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, 'Sala Direttivo');
    await tester.scrollUntilVisible(
      find.text('Formazioni'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formazioni'));
    await tester.pumpAndSettle();

    expect(find.text('Rossi'), findsOneWidget);
    await tester.tap(find.text('FUTURO'));
    await tester.pumpAndSettle();
    // Formazione FUTURO: Neri in porta e Verdi; Rossi non c'è.
    expect(find.text('Verdi'), findsOneWidget);
    expect(find.text('Neri'), findsOneWidget);
    expect(find.text('Rossi'), findsNothing);
  });
}
