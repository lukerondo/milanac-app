import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';

import 'home_test.dart';

/// Apre una voce del menu laterale (scorrendo se serve).
Future<void> openSection(WidgetTester tester, String title) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  final item = find.descendant(
    of: find.byType(Drawer),
    matching: find.text(title),
  );
  await tester.scrollUntilVisible(
    item,
    200,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('carta valida adesso: la blu batte la nero/oro, le scadute non contano', () {
    final now = DateTime(2026, 10, 10, 17);
    SpecialCard card(String id, String player, CardSpecial kind, int daysAgo) =>
        SpecialCard(
          id: id,
          playerId: player,
          kind: kind,
          reparto: 'ATT',
          bonus: 3,
          startsAt: now.subtract(Duration(days: daysAgo)),
          endsAt: now.subtract(Duration(days: daysAgo - 7)),
          team: Team.milanac,
        );
    final cards = [
      card('a', 'p1', CardSpecial.neroOro, 1),
      card('b', 'p1', CardSpecial.blu, 3),
      card('c', 'p2', CardSpecial.neroOro, 9), // scaduta
      card('d', 'p3', CardSpecial.neroOro, 6),
      card('e', 'p3', CardSpecial.neroOro, 2), // più recente
    ];
    final active = activeSpecialCards(cards, now);
    expect(active['p1']?.id, 'b');
    expect(active.containsKey('p2'), isFalse);
    expect(active['p3']?.id, 'e');
    expect(overallWith(82, active['p1']), 85);
    expect(overallWith(98, active['p1']), 99);
    expect(overallWith(null, active['p1']), isNull);
    expect(cards[0].activeAt(now.add(const Duration(days: 6))), isFalse);
  });

  testWidgets('Carte speciali: settimana in corso, storico, carta mia speciale '
      'e assegnazione dal risultato', (tester) async {
    await startAppAt(tester, todayAt(17));

    await openSection(tester, 'Carte speciali');
    expect(find.text('QUESTA SETTIMANA'), findsOneWidget);
    expect(find.text('ATT · Marco Rossi'), findsOneWidget);
    expect(find.text('POR · Andrea Neri'), findsOneWidget);
    expect(find.textContaining('Blu elettrico +5'), findsOneWidget);
    expect(find.text('BLU ELETTRICO'), findsOneWidget);
    expect(find.text('CARTA DELLA SETTIMANA'), findsNWidgets(3));
    await tester.scrollUntilVisible(
      find.text('STORICO'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Milan AC 0–1 Sporting Joypad'), findsOneWidget);

    // La mia carta: overall 82 + 5 e la nota della carta nero/oro.
    await openSection(tester, 'La mia carta');
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('Carta nero/oro +5'), findsOneWidget);
    expect(find.text('CARTA DELLA SETTIMANA'), findsOneWidget);
    // Walkout con la carta speciale.
    await tester.ensureVisible(find.text('Walkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Walkout'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('CARTA DELLA SETTIMANA +5'), findsOneWidget);
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();

    // Dal risultato dell'amichevole del Futuro il Direttivo assegna una nero/oro.
    await openSection(tester, 'Risultati');
    await tester.scrollUntilVisible(
      find.text('Real Brianza'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Real Brianza'));
    await tester.pumpAndSettle();
    expect(find.text('CARTE SPECIALI'), findsOneWidget);
    expect(find.text('Le carte si assegnano dopo il risultato.'), findsNothing);
    await tester.tap(find.text('Assegna carte speciali'));
    await tester.pumpAndSettle();
    expect(find.text('Carte speciali della partita'), findsOneWidget);
    await tester.tap(find.text('CEN · Centrocampo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paolo Verdi (CC)').last);
    await tester.pumpAndSettle();
    expect(find.text('+5'), findsWidgets);
    await tester.tap(find.text('Assegna le carte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carte assegnate: 1 nuove'), findsOneWidget);
    expect(find.text('Paolo Verdi'), findsOneWidget);
    expect(find.text('Modifica carte speciali'), findsOneWidget);
  });
}
