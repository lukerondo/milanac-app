import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Sala Direttivo: avviso a tutti e chat riservata', (
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
    await goToSection(tester, 'Sala Direttivo');
    expect(find.text('senza risposta stasera'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Avviso a tutti'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avviso a tutti'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Stasera si gioca alle 22');
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();
    expect(
      find.text('Avviso inviato in MILANAC Main a tutto il club.'),
      findsOneWidget,
    );

    await goToSection(tester, 'Chat');
    // Il canale riservato compare (la demo è Direttivo), con il lucchetto.
    expect(find.text('Sala Direttivo'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    await tester.tap(find.text('MILANAC Main'));
    await tester.pumpAndSettle();
    expect(find.text('AVVISO DEL DIRETTIVO'), findsOneWidget);
    expect(find.text('Stasera si gioca alle 22'), findsOneWidget);
  });
}
