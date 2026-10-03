import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

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
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formazione'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('3-5-2'));
    await tester.pumpAndSettle();
    expect(find.text('Rossi'), findsOneWidget);
  });
}
