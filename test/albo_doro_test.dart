import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/albo_doro/trophies_repository.dart';
import 'package:milanac/features/albo_doro/trophy.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<void> openAlbo(WidgetTester tester) async {
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
  await goToSection(tester, "Albo d'oro");
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('stagione calcistica da luglio a giugno', () {
    expect(currentSeasonLabel(DateTime(2026, 10, 3)), '2026/27');
    expect(currentSeasonLabel(DateTime(2026, 3, 1)), '2025/26');
    expect(currentSeasonLabel(DateTime(2099, 7, 1)), '2099/00');
  });

  testWidgets('Albo d\'oro: cambio stagione e nuovo trofeo', (tester) async {
    await openAlbo(tester);

    // Stagione in corso (2026/27) ancora vuota.
    expect(find.text('2026/27'), findsOneWidget);
    expect(find.textContaining('Bacheca ancora vuota'), findsOneWidget);

    // Le stagioni in alto: quella precedente ha 5 trofei.
    await tester.tap(find.text('2025/26'));
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('TROFEI'), findsOneWidget);
    expect(find.text('nella stagione 2025/26'), findsOneWidget);
    expect(find.bySemanticsLabel('Coppa FVPA'), findsOneWidget);

    // Dettaglio del trofeo.
    await tester.tap(find.bySemanticsLabel('Coppa FVPA'));
    await tester.pumpAndSettle();
    expect(find.text('Finale vinta 3-2 ai supplementari.'), findsOneWidget);
    Navigator.of(
      tester.element(find.text('Finale vinta 3-2 ai supplementari.')),
    ).pop();
    await tester.pumpAndSettle();

    // Il Direttivo aggiunge un trofeo alla stagione mostrata.
    await tester.ensureVisible(find.text('Aggiungi un trofeo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi un trofeo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome del trofeo'),
      'Supercoppa',
    );
    await tester.tap(find.text('Medaglia'));
    await tester.ensureVisible(find.text('Metti in bacheca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metti in bacheca'));
    await tester.pumpAndSettle();

    // Resta sulla stagione mostrata, con un trofeo in più.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('nella stagione 2025/26'), findsOneWidget);
    expect(find.bySemanticsLabel('Supercoppa'), findsOneWidget);
  });

  testWidgets('Albo d\'oro: il trofeo messo in bacheca da un altro telefono si '
      'vede riaprendo la pagina e al ritorno in primo piano', (tester) async {
    final server = DemoTrophiesRepository();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [trophiesRepositoryProvider.overrideWithValue(server)],
    );
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, "Albo d'oro");
    expect(find.textContaining('Bacheca ancora vuota'), findsOneWidget);

    // Un trofeo nella stagione in corso, messo da un altro telefono.
    final season = await server.ensureSeason(currentSeasonLabel());
    await server.save(
      Trophy(id: '', seasonId: season.id, name: 'Coppa d\'autunno'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coppa d\'autunno'), findsNothing);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    await goToSection(tester, "Albo d'oro");
    expect(find.text('Coppa d\'autunno'), findsOneWidget);

    // Con la pagina aperta: al ritorno in primo piano.
    await server.save(
      Trophy(id: '', seasonId: season.id, name: 'Coppa di Natale 2026'),
    );
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('Coppa di Natale 2026'), findsOneWidget);
  });
}
