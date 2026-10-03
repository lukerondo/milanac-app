import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/albo_doro/trophy.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

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
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text("Albo d'oro"));
  await tester.pumpAndSettle();
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
    expect(find.text('Stagione 2026/27'), findsOneWidget);
    expect(find.textContaining('Bacheca ancora vuota'), findsOneWidget);

    // Selettore in alto a destra: stagione precedente con 5 trofei.
    await tester.tap(find.text('Stagione 2026/27'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stagione 2025/26').last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Coppa FVPA'), findsOneWidget);

    // Dettaglio del trofeo.
    await tester.tap(find.bySemanticsLabel('Coppa FVPA'));
    await tester.pumpAndSettle();
    expect(find.text('Finale vinta 3-2 ai supplementari.'), findsOneWidget);
    Navigator.of(tester.element(find.text('Finale vinta 3-2 ai supplementari.'))).pop();
    await tester.pumpAndSettle();

    // Il Direttivo aggiunge un trofeo alla stagione mostrata.
    await tester.tap(find.text('Aggiungi trofeo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome del trofeo'), 'Supercoppa');
    await tester.tap(find.text('Medaglia'));
    await tester.ensureVisible(find.text('Metti in bacheca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metti in bacheca'));
    await tester.pumpAndSettle();

    expect(find.text('Stagione 2025/26'), findsOneWidget);
    expect(find.bySemanticsLabel('Supercoppa'), findsOneWidget);
  });
}
