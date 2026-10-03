import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/tornei/tournaments_repository.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('classifica: punti, differenza reti, gol fatti', () {
    final rows = sortStandings(const [
      StandingRow(
        teamName: 'B',
        won: 1,
        drawn: 1,
        goalsFor: 3,
        goalsAgainst: 1,
      ),
      StandingRow(
        teamName: 'A',
        won: 1,
        drawn: 1,
        goalsFor: 5,
        goalsAgainst: 3,
      ),
      StandingRow(teamName: 'C', won: 2, lost: 3),
    ]);
    expect(rows.map((r) => r.teamName), ['C', 'A', 'B']);
    expect(rows.first.points, 6);
    expect(rows.first.played, 5);
  });

  testWidgets('Tornei: elenco, filtro, dettaglio con classifica', (
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
    await goToSection(tester, 'Tornei');

    expect(find.text('FVPA Serie B'), findsOneWidget);
    expect(find.text('FVPA · 1° posto · 7 pt'), findsOneWidget);
    expect(find.text('Coppa Riserve'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'FUTURO'));
    await tester.pumpAndSettle();
    expect(find.text('FVPA Serie B'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tutte'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FVPA Serie B'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'TORNEO'), findsOneWidget);
    expect(find.text('CLASSIFICA'), findsOneWidget);
    expect(find.text('Dinamo Pixel'), findsWidgets);
    await tester.scrollUntilVisible(find.text('PARTITE'), 200);
    expect(find.text('PARTITE'), findsOneWidget);
  });
}
