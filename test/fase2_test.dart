import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_reader.dart';
import 'package:milanac/features/rosa/rosa_page.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/ui.dart';

import 'helpers.dart';
import 'rosa_view.dart';

Future<void> openSection(WidgetTester tester, String title) =>
    goToSection(tester, title);

Future<void> startApp(WidgetTester tester) async {
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
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Rosa: modifica del numero di maglia', (tester) async {
    await startApp(tester);
    await openSection(tester, 'Rosa completa');
    // L'elenco classico (la vista predefinita sono le mini carte).
    await showRosaAs(tester, RosaView.elenco);

    await tester.scrollUntilVisible(
      find.text('Marco Rossi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    // Si apre la carta; il Direttivo modifica i dati del membro da lì.
    expect(find.text('CARTA GIOCATORE'), findsOneWidget);
    await tester.ensureVisible(find.text('Dati del membro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dati del membro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Numero'), '11');
    await tester.ensureVisible(find.text('Salva'));
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('Squadre MILANAC e FUTURO: spostamenti', (tester) async {
    await startApp(tester);
    await openSection(tester, 'Sala Direttivo');

    // Rosa e squadre: Rossi passa anche in FUTURO.
    await tester.scrollUntilVisible(
      find.text('Rosa e squadre'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rosa e squadre'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterPill, 'Futuro · 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Marco Rossi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final rossiCard = find.ancestor(
      of: find.text('Marco Rossi'),
      matching: find.byType(AppCard),
    );
    await tester.ensureVisible(rossiCard);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: rossiCard,
        matching: find.widgetWithText(FilterChip, 'Milan AC Futuro'),
      ),
    );
    await tester.pumpAndSettle();
    // I filtri restano in alto.
    expect(find.widgetWithText(FilterPill, 'Futuro · 3'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    // Filtro FUTURO in Rosa: Neri (entrambe), Verdi e ora Rossi.
    await openSection(tester, 'Rosa completa');
    await showRosaAs(tester, RosaView.elenco);
    await tester.tap(find.widgetWithText(FilterPill, 'Futuro · 3'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Paolo Verdi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Andrea Neri'), findsOneWidget);
    expect(find.text('Luca Bianchi'), findsNothing);
  });

  testWidgets('Regolamento: mostra il testo e permette la modifica', (
    tester,
  ) async {
    await startApp(tester);
    await openSection(tester, 'Regolamento & Storia');

    // Lettura su fondo scuro con gli articoli dell'ultima versione pubblicata.
    expect(find.text('Regolamento'), findsWidgets);
    expect(find.text('ORGANIGRAMMA'), findsOneWidget);
    expect(find.textContaining('Versione 1'), findsOneWidget);

    // Il Direttivo apre la bozza, aggiunge un articolo e pubblica la versione 2.
    await tester.tap(find.byTooltip('Modifica il regolamento'));
    await tester.pumpAndSettle();
    expect(find.text('BOZZA DEL REGOLAMENTO'), findsOneWidget);
    await tester.tap(find.text('Nuovo articolo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Art. 4 – Chat',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Testo'),
      'Niente insulti in chat.',
    );
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Art. 4 – Chat'), findsOneWidget);
    await tester.tap(find.text('PUBBLICA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pubblica'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Versione 2 pubblicata'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ART. 4 – CHAT'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(RulesReader),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('ART. 4 – CHAT'), findsOneWidget);

    // Storia: il racconto e, sotto, l'organigramma (dal regolamento).
    await tester.tap(find.text('Storia'));
    await tester.pumpAndSettle();
    expect(find.text('LA NOSTRA STORIA'), findsOneWidget);
    expect(find.textContaining('settembre 2025'), findsOneWidget);
    expect(find.byTooltip('Modifica la storia'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ORGANIGRAMMA'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(StoryReader),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('ORGANIGRAMMA'), findsOneWidget);
  });

  testWidgets('Contatti social modificabili dal Direttivo', (tester) async {
    await startApp(tester);
    await goToSection(tester, 'Club');
    await tester.scrollUntilVisible(
      find.text('Instagram'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Instagram'), findsOneWidget);

    await tester.tap(find.byTooltip('Modifica contatti'));
    await tester.pumpAndSettle();
    expect(find.text('CONTATTI SOCIAL'), findsOneWidget);

    // Elimina il primo contatto (Instagram) e salva.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();
    await tester.tap(find.text('SALVA'));
    await tester.pumpAndSettle();

    expect(find.text('Instagram'), findsNothing);
    expect(find.text('WhatsApp'), findsOneWidget);
  });
}
