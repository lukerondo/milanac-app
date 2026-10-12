import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/calendario/calendario_page.dart';
import 'package:milanac/shared/ui.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;

/// Home, Presenze, Calendario, Formazione e Sala Direttivo con l'aspetto "Chiaro": ogni
/// schermata usa la tavolozza chiara e si apre senza errori né testo che sborda.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startLight(WidgetTester tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    await container.read(appearanceProvider.notifier).set(Appearance.chiaro);
    await tester.pumpAndSettle();
    return container;
  }

  /// La schermata con [anchor] usa la tavolozza chiara e finora non ci sono errori
  /// (nemmeno righe che sbordano).
  void expectLight(WidgetTester tester, Finder anchor) {
    expect(anchor, findsWidgets);
    final context = tester.element(anchor.first);
    expect(Theme.of(context).brightness, Brightness.light);
    expect(context.pal.isDark, isFalse);
    expect(tester.takeException(), isNull);
  }

  /// Scorre fino in fondo la lista [scrollable] (la prima della pagina se manca).
  Future<void> scrollToEnd(WidgetTester tester, [Finder? scrollable]) async {
    final list = scrollable ?? find.byType(Scrollable).first;
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, -500), warnIfMissed: false);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Chiude il foglio o il dialogo che contiene [inside].
  Future<void> close(WidgetTester tester, Finder inside) async {
    Navigator.of(tester.element(inside.first)).pop();
    await tester.pumpAndSettle();
  }

  /// Torna indietro da una pagina a schermo intero.
  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('Tema chiaro: Home, Presenze e Calendario', (tester) async {
    await startLight(tester);

    // Home: stasera, prossima partita, ultimo risultato e Mondo Proclub.
    expectLight(tester, find.text('STASERA · MILAN AC'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('MONDO PROCLUB'));

    // Presenze: la serata di oggi, gli elenchi e lo storico di un giocatore.
    await goToSection(tester, 'Presenze');
    expectLight(tester, find.text('OGGI · MILAN AC'));
    final day = find
        .descendant(
          of: find.byKey(const ValueKey('presenze-giorno')),
          matching: find.byType(Scrollable),
        )
        .first;
    await scrollToEnd(tester, day);
    expectLight(tester, find.textContaining('SENZA RISPOSTA ·'));
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    expectLight(tester, find.textContaining('Storico presenze'));
    await close(tester, find.textContaining('Storico presenze'));

    // Il mese intero e le statistiche.
    await tester.tap(find.bySemanticsLabel(RegExp('Mostra il mese intero')));
    await tester.pumpAndSettle();
    expectLight(tester, find.bySemanticsLabel(RegExp('Mostra la settimana')));
    await tester.tap(find.text('Statistiche'));
    await tester.pumpAndSettle();
    expectLight(tester, find.textContaining('puntuale'));

    // Calendario: tutte le squadre, i dettagli di un evento e l'editor.
    await goToSection(tester, 'Calendario');
    expectLight(tester, find.text('QUESTA SETTIMANA'));
    final page = find.byType(CalendarioPage);
    await tester.tap(
      find.descendant(
        of: page,
        matching: find.widgetWithText(FilterPill, 'Tutte'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: page, matching: find.byType(EventRow)).first,
    );
    await tester.pumpAndSettle();
    expectLight(tester, find.text('Modifica'));
    await close(tester, find.text('Modifica'));
    await scrollToEnd(
      tester,
      find.descendant(of: page, matching: find.byType(Scrollable)).first,
    );
    // In fondo gli ultimi risultati.
    expectLight(tester, find.text('Dinamo Pixel'));
    await tester.tap(find.text('Nuovo evento'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('NUOVO EVENTO'));
    await scrollToEnd(tester, find.byType(Scrollable).last);
    expectLight(tester, find.text('Salva evento'));
  });

  testWidgets('Tema chiaro: Formazione e Sala Direttivo', (tester) async {
    await startLight(tester);

    // Formazione non ancora pubblicata, poi l'editor: scelta del giocatore e pubblicazione.
    await goToSection(tester, 'Formazione');
    expectLight(tester, find.textContaining('non è ancora stata pubblicata'));
    await tester.tap(find.text('Prepara la formazione'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('FORMAZIONI'));
    await tester.ensureVisible(find.text('9 Rossi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 Rossi'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('CHI GIOCA ATT?'));
    await close(tester, find.text('CHI GIOCA ATT?'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('PANCHINA'));
    await tester.tap(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('Pubblicare la formazione?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Pubblica'));
    await tester.pumpAndSettle();
    await back(tester);
    // La sezione con la formazione pubblicata.
    expectLight(tester, find.text('Pubblicata oggi'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('Condividi PDF'));

    // Sala Direttivo: da fare oggi, minuti voce e gestione.
    await goToSection(tester, 'Sala Direttivo');
    expectLight(tester, find.text('DA FARE OGGI'));
    expectLight(tester, find.text('Minuti voce del mese'));

    // Presenze di stasera, con la correzione di un giocatore.
    await tester.tap(find.text('Senza risposta stasera'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('PRESENZE DI STASERA'));
    await tester.tap(find.text('Luca Bianchi'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('Segna per lui (Direttivo):'));
    await close(tester, find.text('Segna per lui (Direttivo):'));
    await scrollToEnd(tester);
    expectLight(tester, find.textContaining('PRESENTI ·'));
    await back(tester);

    // Gestione in fondo: avviso a tutti e Rosa e squadre (con i rimossi).
    await scrollToEnd(tester);
    expectLight(tester, find.text('Contatti social'));
    await tester.tap(find.text('Avviso a tutti'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('Avviso a tutto il club'));
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rosa e squadre'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('ROSA E SQUADRE'));
    await scrollToEnd(tester, find.byType(Scrollable).last);
    expectLight(tester, find.text('RIMOSSI'));
    await back(tester);
    expectLight(tester, find.text('Contatti social'));
  });
}
