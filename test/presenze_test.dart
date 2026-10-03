import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/main.dart';

Future<void> openPresenze(WidgetTester tester) async {
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
  await tester.tap(find.text('Presenze'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('statistiche: il ritardo conta come presenza', () {
    final d = DateTime(2026, 10, 1);
    final stats = AttendanceStats([
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.presente),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.ritardo),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.assente),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.assente),
    ]);
    expect(stats.percent, 50);
    expect(stats.late, 1);
  });

  testWidgets('il giocatore segna la presenza', (tester) async {
    await openPresenze(tester);
    expect(find.text('STASERA'), findsOneWidget);
    expect(find.textContaining('Non hai ancora risposto'), findsOneWidget);
    expect(find.text('In ritardo, arrivo alle 21:50 · Esco tardi da lavoro'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente').first);
    await tester.pumpAndSettle();

    expect(find.text('Presente alle 21:30'), findsWidgets);
    expect(find.textContaining('Non hai ancora risposto'), findsNothing);
  });

  testWidgets('assenza con nota e storico del giocatore', (tester) async {
    await openPresenze(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Assente').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Febbre');
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.text('Assente · Febbre'), findsWidgets);

    // Apre lo storico di Marco Rossi.
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Storico presenze'), findsOneWidget);
    expect(find.text('Segna per questo giocatore (Direttivo):'), findsOneWidget);
  });
}
