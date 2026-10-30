import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/notify_prefs.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/errors.dart';
import 'package:milanac/core/italian_time.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/calendario/events_repository.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/presenze/attendance_repository.dart';

import 'home_test.dart' show startAppAt, todayInItalyAt;

/// La partita di oggi alle 21:30 italiane (id restituito).
Future<String> _matchToday(ProviderContainer container, DateTime now) async {
  final today = italianClock(now);
  final repo = container.read(eventsRepositoryProvider);
  await repo.save(
    ClubEvent(
      id: '',
      type: EventType.torneo,
      title: 'FVPA Serie B – 4ª giornata vs Lupi Grigi',
      startsAt: DateTime.utc(today.year, today.month, today.day, 21, 30),
    ),
  );
  final events = await repo.watchAll().first;
  return events.firstWhere((e) => e.title.contains('Lupi Grigi')).id;
}

const _giocatore = Profile(
  id: 'demo',
  displayName: 'Demo Giocatore',
  role: ClubRole.giocatore,
  registrationCompleted: true,
  notifyPrefs: NotifyPrefs({NotifyCategory.partite}),
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('Chiamata in lobby (demo come il server): solo le partite, nelle ore '
      'della partita, una ogni 3 minuti', () async {
    var now = todayInItalyAt(19, 0);
    final repo = DemoEventsRepository(clock: () => now);
    final today = italianClock(now);
    await repo.save(
      ClubEvent(
        id: '',
        type: EventType.amichevole,
        title: 'Amichevole vs Orsi',
        startsAt: DateTime.utc(today.year, today.month, today.day, 21, 30),
      ),
    );
    await repo.save(
      ClubEvent(
        id: '',
        type: EventType.allenamento,
        title: 'Allenamento',
        startsAt: DateTime.utc(today.year, today.month, today.day, 21, 30),
      ),
    );
    final events = await repo.watchAll().first;
    final match = events.firstWhere((e) => e.title == 'Amichevole vs Orsi').id;
    final training = events.firstWhere((e) => e.title == 'Allenamento').id;

    Future<String> refused(String id) async {
      try {
        await repo.callToLobby(id);
      } on AppError catch (e) {
        return e.message;
      }
      fail('doveva rifiutare');
    }

    // Alle 19:00 mancano due ore e mezza.
    expect(await refused(match), contains('nelle ore della partita'));
    expect(await refused(training), 'Partita non trovata.');
    now = todayInItalyAt(21, 0);
    expect(await repo.callToLobby(match), now);
    now = now.add(const Duration(minutes: 2));
    expect(await refused(match), contains('chiamata da poco'));
    now = now.add(const Duration(minutes: 1));
    expect(await repo.callToLobby(match), now);
    expect(repo.lobbyCalls[match], hasLength(2));
    // Due ore dopo l'inizio non si chiama più.
    now = todayInItalyAt(23, 31);
    expect(await refused(match), contains('nelle ore della partita'));
  });

  testWidgets('Match Day del Direttivo: quando arrivano i promemoria, poi '
      '"Chiama" la squadra in lobby (non due volte di fila)', (tester) async {
    var now = todayInItalyAt(18, 54);
    final container = await startAppAt(tester, now, clock: () => now);
    await _matchToday(container, now);
    await tester.pumpAndSettle();

    expect(find.text('Promemoria alle 20:30 e alle 21:20'), findsOneWidget);
    // Prima delle 19:30 non si chiama ancora nessuno.
    expect(find.text('Chiama'), findsNothing);

    now = todayInItalyAt(20, 45);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Promemoria per la lobby alle 21:20'), findsOneWidget);
    await tester.ensureVisible(find.text('Chiama'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiama'));
    await tester.pumpAndSettle();
    expect(find.text('Chiamare la squadra in lobby?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Chiama'));
    await tester.pumpAndSettle();
    expect(find.text('Squadra chiamata in lobby.'), findsOneWidget);
    final repo =
        container.read(eventsRepositoryProvider) as DemoEventsRepository;
    expect(repo.lobbyCalls.values.single, hasLength(1));

    // Subito dopo: la chiamata non riparte.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiama'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Chiama'));
    await tester.pumpAndSettle();
    expect(find.textContaining('chiamata da poco'), findsOneWidget);
    expect(repo.lobbyCalls.values.single, hasLength(1));

    // Dieci minuti prima: lobby aperta. A partita iniziata il Direttivo può ancora
    // chiamare chi manca.
    now = todayInItalyAt(21, 22);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Lobby aperta: si entra!'), findsOneWidget);
    now = todayInItalyAt(21, 40);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    // Con il tabellone più basso ("IN CORSO") la Home è scorsa oltre la card: si risale.
    await tester.scrollUntilVisible(
      find.text('Manca qualcuno? Chiamalo in lobby'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Manca qualcuno? Chiamalo in lobby'), findsOneWidget);
    expect(find.text('Chiama'), findsOneWidget);
  });

  testWidgets('Giocatore con i promemoria spenti: lo dice e porta alle '
      'impostazioni, dove c\'è "Promemoria partita"; niente "Chiama"', (
    tester,
  ) async {
    final now = todayInItalyAt(18, 54);
    final container = await startAppAt(
      tester,
      now,
      overrides: [
        profileProvider.overrideWith((ref) => Stream.value(_giocatore)),
      ],
    );
    await _matchToday(container, now);
    await tester.pumpAndSettle();

    expect(find.text('Promemoria partita spenti'), findsOneWidget);
    expect(find.text('Chiama'), findsNothing);
    await tester.ensureVisible(find.text('Promemoria partita spenti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promemoria partita spenti'));
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, 'Promemoria partita');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets(
    'Direttivo: spegne i promemoria nelle impostazioni e il Match Day '
    'lo mostra',
    (tester) async {
      final now = todayInItalyAt(18, 54);
      final container = await startAppAt(tester, now);
      await _matchToday(container, now);
      await tester.pumpAndSettle();
      container
          .read(demoProfileProvider.notifier)
          .update(
            (p) => p.withNotifyPrefs(
              p.notifyPrefs.set(NotifyCategory.partite, false),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Promemoria partita spenti'), findsOneWidget);
      container
          .read(demoProfileProvider.notifier)
          .update(
            (p) => p.withNotifyPrefs(
              p.notifyPrefs.set(NotifyCategory.partite, true),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Promemoria alle 20:30 e alle 21:20'), findsOneWidget);
      expect(
        const NotifyPrefs({NotifyCategory.partite}).toJson()['partite'],
        isFalse,
      );
    },
  );

  testWidgets(
    'Chi è assente non riceve i promemoria e il Match Day lo dice; il '
    'Direttivo assente può comunque chiamare la squadra',
    (tester) async {
      var now = todayInItalyAt(17, 30);
      final container = await startAppAt(
        tester,
        now,
        clock: () => now,
        overrides: [
          profileProvider.overrideWith(
            (ref) => Stream.value(
              const Profile(
                id: 'demo',
                displayName: 'Demo Giocatore',
                role: ClubRole.giocatore,
                registrationCompleted: true,
              ),
            ),
          ),
        ],
      );
      await _matchToday(container, now);
      await container
          .read(attendanceRepositoryProvider)
          .save(
            AttendanceEntry(
              playerId: 'demo',
              date: italianDay(now),
              status: AttendanceStatus.assente,
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Sei assente: niente promemoria'), findsOneWidget);
      expect(find.text('Promemoria alle 20:30 e alle 21:20'), findsNothing);
      expect(find.text('Chiama'), findsNothing);
    },
  );

  testWidgets(
    'Direttivo assente: niente promemoria per sé, ma "Chiama" resta',
    (tester) async {
      final now = todayInItalyAt(20, 45);
      final container = await startAppAt(tester, now);
      await _matchToday(container, now);
      await container
          .read(attendanceRepositoryProvider)
          .save(
            AttendanceEntry(
              playerId: 'demo',
              date: italianDay(now),
              status: AttendanceStatus.assente,
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Chiama la squadra in lobby'), findsOneWidget);
      expect(find.text('Chiama'), findsOneWidget);
    },
  );
}
