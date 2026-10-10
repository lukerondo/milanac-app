import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('demo: intro, poi Home, Mondo Proclub e menu laterale', (
    tester,
  ) async {
    // Schermo di uno smartphone (1080x2340).
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MilanacApp()));
    await tester.pump();
    expect(find.textContaining('Caricamento'), findsOneWidget);

    // Salta l'intro con un tocco.
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    expect(find.text('MONDO PROCLUB'), findsOneWidget);
    expect(find.text('PRESENZE'), findsOneWidget);

    // Le notizie stanno in Mondo Proclub, seconda scheda.
    await goToSection(tester, 'Mondo Proclub');
    expect(find.text('Video dei creator'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('Notizie'));
    await tester.pumpAndSettle();
    expect(find.text('Leggi la notizia'), findsWidgets);

    // Il menu è a gruppi; la Sala Direttivo c'è perché la demo è Direttivo.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('SQUADRA'), findsOneWidget);
    expect(find.text('CLUB'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sala Direttivo'),
      100,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Sala Direttivo'), findsOneWidget);
    expect(find.text('Demo Direttivo'), findsOneWidget);
    expect(find.text('Direttivo · Capitano, Gestore'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.descendant(of: find.byType(Drawer), matching: find.text('Chat')),
      -100,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('CHAT'), findsOneWidget);
  });

  test('intro state parte da false', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(introDoneProvider), isFalse);
    c.read(introDoneProvider.notifier).complete();
    expect(c.read(introDoneProvider), isTrue);
  });
}
