import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

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

  testWidgets('Rosa: il Direttivo approva una richiesta di accesso', (
    tester,
  ) async {
    await startApp(tester);
    await openSection(tester, 'Rosa completa');

    expect(find.text('RICHIESTE DI ACCESSO'), findsOneWidget);
    expect(find.text('Nuovo Iscritto'), findsOneWidget);

    expect(
      find.textContaining('Chiede di entrare come Giocatore'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Approva come Giocatore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approva come Giocatore'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nuovo Iscritto approvato come Giocatore (MILANAC).'),
      findsOneWidget,
    );

    expect(find.text('RICHIESTE DI ACCESSO'), findsNothing);
    expect(find.text('Diavolo_9 · Dal 3 feb 2025'), findsOneWidget);
    // Ora è in fondo, tra i giocatori.
    await tester.scrollUntilVisible(find.text('Nuovo Iscritto'), 200);
    expect(find.text('Nuovo Iscritto'), findsOneWidget);
  });

  testWidgets('Rosa: il Direttivo rifiuta una richiesta (con conferma)', (
    tester,
  ) async {
    await startApp(tester);
    await openSection(tester, 'Rosa completa');

    await tester.tap(find.text('Rifiuta'));
    await tester.pumpAndSettle();
    expect(find.text('Rifiutare Nuovo Iscritto?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Rifiuta'));
    await tester.pumpAndSettle();

    expect(find.text('RICHIESTE DI ACCESSO'), findsNothing);
    expect(find.text('Nuovo Iscritto'), findsNothing);
  });

  testWidgets('Rosa: modifica del numero di maglia', (tester) async {
    await startApp(tester);
    await openSection(tester, 'Rosa completa');

    await tester.scrollUntilVisible(find.text('Marco Rossi'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    // Si apre la carta; il Direttivo modifica i dati del membro da lì.
    expect(find.text('CARTA GIOCATORE'), findsOneWidget);
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

  testWidgets('Rosa: squadre MILANAC e FUTURO', (tester) async {
    await startApp(tester);
    await openSection(tester, 'Rosa completa');

    // Richiesta approvata direttamente in MILANAC FUTURO.
    await tester.ensureVisible(find.text('Nuovo Iscritto'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'MILANAC FUTURO'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'MILANAC'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approva come Giocatore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approva come Giocatore'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nuovo Iscritto approvato come Giocatore (MILANAC FUTURO).'),
      findsOneWidget,
    );

    // Filtro FUTURO: Neri (entrambe), Verdi e il nuovo iscritto; non Rossi.
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'FUTURO (3)'),
      -200,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'FUTURO (3)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Paolo Verdi'), 200);
    expect(find.text('Andrea Neri'), findsOneWidget);
    expect(find.text('Marco Rossi'), findsNothing);
  });

  testWidgets('Regolamento: mostra il testo e permette la modifica', (
    tester,
  ) async {
    await startApp(tester);
    await openSection(tester, 'Regolamento & Storia');

    expect(find.text('Regolamento interno'), findsOneWidget);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '# Nuovo regolamento\n- Regola uno',
    );
    await tester.tap(find.text('SALVA'));
    await tester.pumpAndSettle();

    expect(find.text('Nuovo regolamento'), findsOneWidget);
    expect(find.text('Regola uno'), findsOneWidget);

    await tester.tap(find.text('Cenni storici'));
    await tester.pumpAndSettle();
    expect(find.text('La nostra storia'), findsOneWidget);
  });

  testWidgets('Contatti social modificabili dal Direttivo', (tester) async {
    await startApp(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Instagram'), findsOneWidget);

    await tester.tap(find.byTooltip('Modifica contatti'));
    await tester.pumpAndSettle();
    expect(find.text('CONTATTI SOCIAL'), findsOneWidget);

    // Elimina il primo contatto (Instagram) e salva.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();
    await tester.tap(find.text('SALVA'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Instagram'), findsNothing);
    expect(find.byTooltip('WhatsApp'), findsOneWidget);
  });
}
