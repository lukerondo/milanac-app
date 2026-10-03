import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/carta/card_stats.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

final rossi = Member(
  id: 'r',
  displayName: 'Marco Rossi',
  gamertag: 'Diavolo_9',
  role: ClubRole.giocatore,
  joinedAt: DateTime(2025, 2, 3),
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('gol dai marcatori scritti a mano', () {
    expect(goalsIn('Rossi 2, Neri', rossi), 2);
    expect(goalsIn('Neri; Diavolo_9 x2', rossi), 2);
    expect(goalsIn('Marco Rossi (3)', rossi), 3);
    expect(goalsIn('rossi', rossi), 1);
    expect(goalsIn('Rossini, Bianchi', rossi), 0);
    expect(goalsIn(null, rossi), 0);
  });

  test('statistiche e livello della carta', () {
    final d = DateTime(2026, 9, 1);
    final stats = CardStats.of(
      rossi,
      attendance: [
        AttendanceEntry(
          playerId: 'r',
          date: d,
          status: AttendanceStatus.presente,
        ),
        AttendanceEntry(
          playerId: 'r',
          date: d,
          status: AttendanceStatus.ritardo,
        ),
        AttendanceEntry(
          playerId: 'r',
          date: d,
          status: AttendanceStatus.assente,
        ),
        AttendanceEntry(
          playerId: 'x',
          date: d,
          status: AttendanceStatus.presente,
        ),
      ],
      matches: [
        ClubMatch(
          id: '1',
          kind: MatchKind.torneo,
          opponent: 'A',
          playedAt: d,
          goalsFor: 2,
          goalsAgainst: 0,
          scorers: 'Rossi 2',
        ),
        ClubMatch(
          id: '2',
          kind: MatchKind.torneo,
          opponent: 'B',
          playedAt: d,
          goalsFor: 0,
          goalsAgainst: 1,
        ),
        // Partita di FUTURO: non conta per chi è solo in MILANAC.
        ClubMatch(
          id: '3',
          kind: MatchKind.torneo,
          opponent: 'C',
          playedAt: d,
          goalsFor: 3,
          goalsAgainst: 0,
          team: Team.futuro,
        ),
      ],
      now: DateTime(2026, 10, 3),
    );
    expect(stats.presence, 67);
    expect(stats.punctuality, 50);
    expect(stats.nights, 2);
    expect(stats.goals, 2);
    expect(stats.months, 20);
    expect(stats.winRate, 50);

    expect(tierOf(null), CardTier.vuota);
    expect(tierOf(60), CardTier.bronzo);
    expect(tierOf(70), CardTier.argento);
    expect(tierOf(80), CardTier.oro);
    expect(tierOf(90), CardTier.rossonera);
  });

  testWidgets('La mia carta: il giocatore imposta il suo overall', (
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
    await goToSection(tester, 'La mia carta');

    expect(find.text('??'), findsOneWidget);
    expect(find.textContaining('Completa la tua carta'), findsOneWidget);
    await tester.tap(find.text('Modifica la mia carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regista'));
    await tester.ensureVisible(find.text('Salva la carta'));
    await tester.tap(find.text('Salva la carta'));
    await tester.pumpAndSettle();

    expect(find.text('70'), findsOneWidget);
    expect(find.text('REGISTA'), findsOneWidget);
    expect(find.textContaining('Completa la tua carta'), findsNothing);
  });

  testWidgets('Rosa: vista a carte', (tester) async {
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
    await goToSection(tester, 'Rosa completa');
    await tester.tap(find.text('Carte'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('ROSSI'), 300);
    // Prima la carta con l'overall più alto (Rossi, 86: rossonera).
    expect(find.text('ROSSI'), findsOneWidget);
    expect(find.text('86'), findsWidgets);
  });
}
