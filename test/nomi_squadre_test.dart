import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/presenze/evening.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/features/risultati/result_ui.dart';
import 'package:milanac/shared/ui.dart';

import 'formazione_test.dart' show openFormationEditor;
import 'helpers.dart';
import 'home_test.dart' show startAppAt, weekdayInItalyAt;

/// Nomi brevi delle squadre nei selettori e nei filtri: "MILANAC" e "FUTURO", tutti e due
/// maiuscoli (accanto a MILANAC non c'è più "Futuro"); il nome intero "MILANAC FUTURO"
/// resta dove si legge per esteso.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('etichette brevi delle squadre: come Team.short', () {
    expect(
      [for (final t in Team.values) teamTabLabel(t)],
      ['MILANAC', 'FUTURO'],
    );
    expect(
      [for (final t in Team.values) teamPillLabel(t)],
      ['MILANAC', 'FUTURO'],
    );
    expect(
      [for (final t in Team.values) t.label],
      ['MILANAC', 'MILANAC FUTURO'],
    );
    final amichevole = ClubMatch(
      id: 'm',
      kind: MatchKind.amichevole,
      opponent: 'Rivali',
      playedAt: DateTime.utc(2026, 11, 4, 21, 30),
      team: Team.futuro,
      home: false,
    );
    expect(matchSubtitle(amichevole), 'Amichevole · FUTURO · in trasferta');
  });

  testWidgets('Presenze, Risultati, Calendario e Formazione: MILANAC e FUTURO '
      'nei selettori', (tester) async {
    await startAppAt(tester, weekdayInItalyAt(17));
    void expectShortNames() {
      expect(find.text('Futuro'), findsNothing);
      expect(find.textContaining(RegExp(r'\bFuturo\b')), findsNothing);
    }

    await goToSection(tester, 'Presenze');
    expect(find.text('MILANAC'), findsWidgets);
    expect(find.text('FUTURO'), findsWidgets);
    expectShortNames();

    await goToSection(tester, 'Risultati');
    expect(find.widgetWithText(FilterPill, 'MILANAC'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'FUTURO'), findsOneWidget);
    expectShortNames();

    await goToSection(tester, 'Calendario');
    expect(find.widgetWithText(FilterPill, 'FUTURO'), findsOneWidget);
    expectShortNames();

    // La fascia in alto dell'editor della formazione.
    await openFormationEditor(tester);
    expect(find.text('MILANAC'), findsWidgets);
    expect(find.text('FUTURO'), findsOneWidget);
    expectShortNames();
    await tester.tap(find.text('FUTURO'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Futuro'), findsNothing);
  });
}
