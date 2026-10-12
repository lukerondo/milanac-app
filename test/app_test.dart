import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('demo: intro, poi Home, Mondo Proclub e schede in basso', (
    tester,
  ) async {
    // Schermo di uno smartphone (1080x2340).
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MilanacApp()));
    await tester.pump();
    // Intro: stemma, barra di caricamento in oro e il motto.
    expect(find.text('MILANO SIAMO NOI'), findsOneWidget);
    expect(find.text('Salta'), findsOneWidget);

    // Salta l'intro con un tocco.
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    expect(find.text('STASERA · MILAN AC'), findsOneWidget);
    // Più in basso, Mondo Proclub in breve.
    await tester.scrollUntilVisible(
      find.text('MONDO PROCLUB'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MONDO PROCLUB'), findsOneWidget);

    // Le notizie stanno in Mondo Proclub, seconda scheda.
    await goToSection(tester, 'Mondo Proclub');
    expect(find.text('Video dei creator'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('Notizie'));
    await tester.pumpAndSettle();
    expect(find.text('Leggi la notizia'), findsWidgets);

    // Cinque schede in basso; nel Club c'è la Sala Direttivo perché la demo è Direttivo.
    expect(find.byType(NavigationBar), findsOneWidget);
    await goToSection(tester, 'Club');
    expect(find.text('CLUB'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sala Direttivo'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sala Direttivo'), findsOneWidget);
    await goToSection(tester, 'Chat');
    expect(find.text('CHAT'), findsOneWidget);
    // Indietro da un'altra scheda riporta alla Home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
  });

  test('intro state parte da false', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(introDoneProvider), isFalse);
    c.read(introDoneProvider.notifier).complete();
    expect(c.read(introDoneProvider), isTrue);
  });
}
