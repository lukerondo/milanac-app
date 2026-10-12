import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/carta/card_stats.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/presenze/attendance_repository.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';
import 'package:milanac/features/traguardi/player_stats.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

final rossi = Member(
  id: 'r',
  displayName: 'Marco Rossi',
  gamertag: 'Diavolo_9',
  role: ClubRole.giocatore,
  joinedAt: DateTime(2025, 2, 3),
);

Member _player(
  String id,
  String name, {
  Set<Team> teams = const {Team.milanac},
  String? gamertag,
  bool active = true,
  ClubRole role = ClubRole.giocatore,
}) => Member(
  id: id,
  displayName: name,
  gamertag: gamertag,
  role: role,
  active: active,
  teams: teams,
  joinedAt: DateTime(2025, 2, 3),
);

ClubMatch _played(String id, String scorers, {Team team = Team.milanac}) =>
    ClubMatch(
      id: id,
      kind: MatchKind.torneo,
      team: team,
      opponent: 'Avversario $id',
      playedAt: DateTime(2026, 9, 1, 21, 30),
      goalsFor: 3,
      goalsAgainst: 1,
      scorers: scorers,
    );

/// Conta quante volte si leggono i numeri dei traguardi.
class _CountingStats implements PlayerStatsRepository {
  var loads = 0;

  @override
  Future<PlayerStats> load(String playerId) async {
    loads++;
    return const PlayerStats();
  }
}

Future<ProviderContainer> _startApp(WidgetTester tester) async {
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
  return container;
}

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

  test('gol: contano solo le partite giocate dalle sue squadre', () {
    final neri = _player('n', 'Andrea Neri', teams: {Team.milanac, Team.futuro});
    final verdi = _player('v', 'Paolo Verdi', teams: {Team.futuro});
    final roster = [rossi, neri, verdi];
    final matches = [
      _played('1', 'Rossi 2, Neri'),
      // Partita del Futuro: Rossi non ci gioca, i suoi "gol" non sono suoi.
      _played('2', 'Rossi 3, Neri, Verdi', team: Team.futuro),
      // Non ancora giocata: i marcatori non contano.
      ClubMatch(
        id: '3',
        kind: MatchKind.amichevole,
        opponent: 'C',
        playedAt: DateTime(2026, 9, 8),
        scorers: 'Rossi',
      ),
    ];
    int goals(Member m) =>
        CardStats.of(
          m,
          attendance: const [],
          matches: matches,
          roster: roster,
          now: DateTime(2026, 10, 3),
        ).goals;
    expect(goals(rossi), 2);
    expect(goals(neri), 2);
    expect(goals(verdi), 1);
  });

  test('gol: omonimi come sul server (prima il nome sulla carta, '
      'un nome ambiguo non assegna gol)', () {
    final marco = _player('m', 'Marco Rossi', gamertag: 'Diavolo_9');
    final luca = _player('l', 'Luca Rossi');
    final bianchi = _player('b', 'Bianchi');
    final gianni = _player('g', 'Gianni Bianchi');
    final players = [marco, luca, bianchi, gianni];

    expect(scorerGoals('Rossi 2', players), isEmpty);
    expect(scorerGoals('Marco Rossi 2, Luca Rossi', players), {'m': 2, 'l': 1});
    expect(scorerGoals('diavolo_9 x2', players), {'m': 2});
    // "Bianchi" è il nome sulla carta di uno e il cognome dell'altro: vince la carta.
    expect(scorerGoals('Bianchi (2), Gianni Bianchi', players), {
      'b': 2,
      'g': 1,
    });

    // Chi è uscito dalla rosa (o è in attesa) non crea omonimie.
    final roster = [
      marco,
      _player('x', 'Ugo Rossi', active: false),
      _player('y', 'Ivo Rossi', role: ClubRole.pending),
    ];
    expect(goalsOf(marco, [_played('1', 'Rossi 3')], roster), 3);
    expect(goalsOf(marco, [_played('1', 'Rossi 3')], [...roster, luca]), 0);
  });

  test('presenze: le risposte per i giorni che devono venire non contano', () {
    AttendanceEntry entry(int day, AttendanceStatus s) =>
        AttendanceEntry(playerId: 'r', date: DateTime(2026, 10, day), status: s);
    final attendance = [
      entry(10, AttendanceStatus.assente),
      entry(12, AttendanceStatus.presente),
      // Risposta data in anticipo per domani.
      entry(13, AttendanceStatus.presente),
    ];
    CardStats at(DateTime now) => CardStats.of(
      rossi,
      attendance: attendance,
      matches: const [],
      roster: [rossi],
      now: now,
    );
    // 12 ottobre, 23:30 in Italia (21:30 UTC, ora legale): il 13 non conta.
    final late = at(DateTime.utc(2026, 10, 12, 21, 30));
    expect(late.nights, 1);
    expect(late.presence, 50);
    // Mezzanotte e mezza in Italia (22:30 UTC): è già il 13.
    final afterMidnight = at(DateTime.utc(2026, 10, 12, 22, 30));
    expect(afterMidnight.nights, 2);
    expect(afterMidnight.presence, 67);
  });

  test('traguardi: i numeri si ricaricano con una carta nuova o una presenza', () async {
    final stats = _CountingStats();
    final container = ProviderContainer(
      overrides: [playerStatsRepositoryProvider.overrideWithValue(stats)],
    );
    addTearDown(container.dispose);
    container.listen(playerStatsProvider('p6'), (_, _) {});
    await container.read(playerStatsProvider('p6').future);
    await pumpEventQueue();
    expect(stats.loads, 1, reason: 'il primo arrivo dei dati non ricarica');

    // Il Direttivo gli assegna una carta nero/oro.
    await container
        .read(specialCardsRepositoryProvider)
        .assign(_played('m2', '2-2', team: Team.futuro), const [
          CardAward(playerId: 'p6', reparto: 'CEN'),
        ]);
    await pumpEventQueue();
    expect(stats.loads, 2);

    // Risponde per stasera.
    final attendance = container.read(attendanceRepositoryProvider);
    await attendance.save(
      AttendanceEntry(
        playerId: 'p6',
        date: DateTime.now(),
        status: AttendanceStatus.presente,
      ),
    );
    await pumpEventQueue();
    expect(stats.loads, 3);

    // Le risposte degli altri non lo riguardano.
    await attendance.save(
      AttendanceEntry(
        playerId: 'p3',
        date: DateTime.now(),
        status: AttendanceStatus.assente,
      ),
    );
    await pumpEventQueue();
    expect(stats.loads, 3);
  });

  test('copyWith: numero, stile, piattaforma e gamertag si possono svuotare', () {
    final m = Member(
      id: 'x',
      displayName: 'Marco Rossi',
      role: ClubRole.giocatore,
      joinedAt: DateTime(2025),
      gamertag: 'Diavolo_9',
      fieldPosition: 'ATT',
      shirtNumber: 9,
      overall: 86,
      playStyle: 'Finalizzatore',
      platform: GamePlatform.ps5,
    );
    final same = m.copyWith(overall: 87);
    expect(same.overall, 87);
    expect(same.shirtNumber, 9);
    expect(same.playStyle, 'Finalizzatore');
    expect(same.platform, GamePlatform.ps5);
    expect(same.gamertag, 'Diavolo_9');

    final cleared = m.copyWith(
      shirtNumber: null,
      playStyle: null,
      platform: null,
      gamertag: null,
    );
    expect(cleared.shirtNumber, isNull);
    expect(cleared.playStyle, isNull);
    expect(cleared.platform, isNull);
    expect(cleared.gamertag, isNull);
    expect(cleared.fieldPosition, 'ATT');
    expect(cleared.overall, 86);
    expect(cleared.cardMap(), {
      'play_style': null,
      'platform': null,
      'field_position': 'ATT',
      'shirt_number': null,
    });
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
      roster: [rossi],
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

  testWidgets('La mia carta: stile di gioco, overall deciso dal Direttivo', (
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

    // L'overall (82) lo ha assegnato il Direttivo; questa settimana ha la carta
    // nero/oro (+5), quindi sulla carta si legge 87. Il giocatore cambia lo stile.
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.textContaining('non ha ancora assegnato'), findsNothing);
    await tester.tap(find.text('Modifica la mia carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regista'));
    await tester.ensureVisible(find.text('Salva la carta'));
    await tester.tap(find.text('Salva la carta'));
    await tester.pumpAndSettle();

    expect(find.text('87'), findsOneWidget);
    expect(find.text('REGISTA'), findsOneWidget);
  });

  testWidgets('Carta e dati del membro: i campi lasciati vuoti si cancellano', (
    tester,
  ) async {
    final container = await _startApp(tester);
    Member rossiNow() =>
        container.read(rosaProvider).value!.firstWhere((m) => m.id == 'p2');
    await goToSection(tester, 'Rosa completa');
    await tester.tap(find.text('Elenco'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Marco Rossi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();

    // Il Direttivo toglie numero, stile e piattaforma dalla carta di Rossi.
    await tester.ensureVisible(find.text('Modifica carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifica carta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Numero'), '');
    await tester.enterText(find.widgetWithText(TextField, 'Stile di gioco'), '');
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'PlayStation 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'PlayStation 5'));
    await tester.ensureVisible(find.text('Salva la carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva la carta'));
    await tester.pumpAndSettle();
    expect(rossiNow().shirtNumber, isNull);
    expect(rossiNow().playStyle, isNull);
    expect(rossiNow().platform, isNull);
    expect(rossiNow().overall, 86);

    // E dai dati del membro il gamertag.
    await tester.ensureVisible(find.text('Dati del membro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dati del membro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Gamertag'), ' ');
    await tester.ensureVisible(find.text('Salva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(rossiNow().gamertag, isNull);
    expect(rossiNow().fieldPosition, 'ATT');
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

    await tester.ensureVisible(find.text('MARCO ROSSI'));
    // Prima la carta con l'overall più alto (Rossi, 86: rossonera).
    expect(find.text('MARCO ROSSI'), findsOneWidget);
    expect(find.text('86'), findsWidgets);
  });
}
