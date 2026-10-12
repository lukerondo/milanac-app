import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/carte/carte_speciali_page.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';

import 'helpers.dart';
import 'home_test.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test(
    'carta valida adesso: la blu batte la nero/oro, le scadute non contano',
    () {
      final now = DateTime(2026, 10, 10, 17);
      SpecialCard card(
        String id,
        String player,
        CardSpecial kind,
        int daysAgo,
      ) => SpecialCard(
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
    },
  );

  testWidgets('Carte speciali: settimana in corso, storico, carta mia speciale '
      'e assegnazione dal risultato', (tester) async {
    await startAppAt(tester, todayAt(17));

    await goToSection(tester, 'Carte speciali');
    expect(find.text('QUESTA SETTIMANA · 2ª GIORNATA'), findsOneWidget);
    expect(
      find.text('Milan AC 3 – 1 Dinamo Pixel · scadono tra 5 giorni'),
      findsOneWidget,
    );
    // La blu elettrico del portiere, poi le nero/oro per reparto.
    expect(find.text('BLU ELETTRICO · POR'), findsOneWidget);
    expect(find.text('Andrea Neri'), findsOneWidget);
    expect(find.text('Tre partite di fila senza subire gol'), findsOneWidget);
    expect(find.text('NERO/ORO DELLA SETTIMANA'), findsOneWidget);
    expect(find.text('Marco Rossi'), findsOneWidget);
    expect(find.text('Demo Direttivo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('STORICO'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1ª giornata · Sporting Joypad 0 – 1'), findsOneWidget);
    expect(find.text('1 carta: Marco Rossi, ATT +5'), findsOneWidget);
    // La giornata dello storico si apre con un tocco.
    await tester.tap(find.text('1ª giornata · Sporting Joypad 0 – 1'));
    await tester.pumpAndSettle();
    expect(find.byType(SpecialCardRow), findsOneWidget);

    // La mia carta: overall 82 + 5 e la carta della settimana sotto.
    await goToSection(tester, 'La mia carta');
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(
      find.text('Carta della settimana · scade tra 5 giorni'),
      findsOneWidget,
    );
    // Walkout con la carta speciale.
    await tester.ensureVisible(find.text('Rivedi il walkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rivedi il walkout'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('CARTA DELLA SETTIMANA'), findsOneWidget);
    expect(
      find.text(
        'Il Direttivo ti ha scelto per il centrocampo della 2ª giornata.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();

    // Dal risultato dell'amichevole del Futuro il Direttivo assegna una nero/oro.
    await goToSection(tester, 'Risultati');
    await tester.scrollUntilVisible(
      find.text('Real Brianza'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Real Brianza'));
    await tester.pumpAndSettle();
    expect(find.text('CARTE SPECIALI DELLA GIORNATA'), findsOneWidget);
    expect(
      find.text('Nessuna carta assegnata per questa partita.'),
      findsOneWidget,
    );
    expect(find.text('Le carte si assegnano dopo il risultato.'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Assegna carte della giornata'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assegna carte della giornata'));
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
    // Il premiato compare nella card della giornata.
    expect(find.text('Verdi'), findsOneWidget);
    expect(find.text('CEN +5'), findsOneWidget);
    expect(find.text('Modifica carte della giornata'), findsOneWidget);
  });
}
