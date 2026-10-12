import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/clock.dart';
import 'package:milanac/core/italian_time.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/presenze/evening.dart';
import 'package:milanac/main.dart';

/// Avvia l'app demo con l'orologio fermo a [now] (e altri provider sostituiti).
Future<ProviderContainer> startAppAt(
  WidgetTester tester,
  DateTime now, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [clockProvider.overrideWithValue(() => now), ...overrides],
  );
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Oggi alle [hour]:[minute] del computer che lancia i test.
DateTime todayAt(int hour, [int minute = 0]) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day, hour, minute);
}

/// L'istante in cui in Italia sono le [hour]:[minute] di oggi (l'app ragiona in ora
/// italiana, qualunque sia il fuso del computer che lancia i test).
DateTime todayInItalyAt(int hour, [int minute = 0]) {
  final t = italianClock(DateTime.now());
  return italyAt(t.year, t.month, t.day, hour, minute);
}

/// L'istante in cui in Italia sono le [hour]:[minute] del giorno indicato.
DateTime italyAt(int year, int month, int day, int hour, [int minute = 0]) =>
    fromItalianClock(DateTime.utc(year, month, day, hour, minute));

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('serata: primo evento del giorno della squadra, altrimenti allenamento '
      '21:30', () {
    final day = DateTime(2026, 10, 3);
    final fallback = eveningEvent(const [], day);
    expect(fallback.type, EventType.allenamento);
    // Gli orari degli eventi sono in ora italiana (vedi ClubEvent.startsAt).
    expect(fallback.startsAt, DateTime.utc(2026, 10, 3, 21, 30));

    final partita = ClubEvent(
      id: 'p',
      type: EventType.amichevole,
      title: 'Amichevole',
      startsAt: DateTime.utc(2026, 10, 3, 22),
    );
    final riunione = ClubEvent(
      id: 'r',
      type: EventType.riunione,
      title: 'Riunione',
      startsAt: DateTime.utc(2026, 10, 3, 20),
    );
    final domani = ClubEvent(
      id: 'd',
      type: EventType.amichevole,
      title: 'Domani',
      startsAt: DateTime.utc(2026, 10, 4, 21),
    );
    final futuro = ClubEvent(
      id: 'f',
      team: Team.futuro,
      type: EventType.torneo,
      title: 'Coppa Futuro',
      startsAt: DateTime.utc(2026, 10, 3, 21),
    );
    expect(
      eveningEvent([domani, riunione, partita, futuro], day).id,
      'f',
      reason: 'con entrambe le squadre vince il primo della serata',
    );
    expect(
      eveningEvent([domani, riunione, partita, futuro], day, teams: {Team.milanac}).id,
      'p',
    );
    expect(
      eveningEvent([futuro, partita], day, teams: {Team.futuro}).id,
      'f',
    );
    expect(
      eveningEvent([futuro], day, teams: {Team.milanac}).type,
      EventType.allenamento,
    );
  });

  test(
    'risposte aperte fino alle 18:30 italiane, anche per i giorni successivi',
    () {
      final day = DateTime(2026, 10, 3);
      expect(answersOpen(day, italyAt(2026, 10, 3, 18, 29)), isTrue);
      expect(answersOpen(day, italyAt(2026, 10, 3, 18, 30)), isFalse);
      expect(answersOpen(day, italyAt(2026, 10, 2, 23)), isTrue);
      expect(answersOpen(day, italyAt(2026, 10, 4, 9)), isFalse);
    },
  );

  testWidgets('Home: i due riquadri e la risposta per stasera', (tester) async {
    await startAppAt(tester, todayInItalyAt(17));

    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    expect(find.text('STASERA · MILAN AC'), findsOneWidget);
    expect(find.text('ALLENAMENTO 21:30'), findsOneWidget);
    expect(find.text('Ci sei? Rispondi entro le 18:30.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('La tua risposta: Presente'), findsOneWidget);

    // Più in basso: Mondo Proclub con gli aggiornamenti e l'ultimo video.
    final home = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('La build da attaccante più forte'),
      300,
      scrollable: home,
    );
    expect(find.text('MONDO PROCLUB'), findsOneWidget);
    expect(find.text('Aggiorna FC 27 prima della partita'), findsOneWidget);
    expect(
      find.text('Aggiorna la PlayStation prima della partita'),
      findsOneWidget,
    );
  });

  testWidgets('Home: prossima partita, ultimo risultato e i collegamenti', (
    tester,
  ) async {
    await startAppAt(tester, todayInItalyAt(17));
    final home = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('MILAN AC – ATLETICO VIRTUALE'),
      200,
      scrollable: home,
    );
    // La competizione nell'etichetta, la giornata sotto il titolo.
    expect(find.text('PROSSIMA PARTITA · FVPA'), findsOneWidget);
    expect(find.textContaining('3ª giornata · '), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('carte speciali assegnate'),
      200,
      scrollable: home,
    );
    expect(find.textContaining('ULTIMO RISULTATO'), findsOneWidget);
    expect(find.text('3 – 1'), findsOneWidget);

    // "Calendario" porta alla scheda Calendario di Partite.
    final calendar = find.widgetWithText(TextButton, 'Calendario');
    await tester.scrollUntilVisible(calendar, -200, scrollable: home);
    await tester.ensureVisible(calendar);
    await tester.pumpAndSettle();
    await tester.tap(calendar);
    await tester.pumpAndSettle();
    expect(find.text('QUESTA SETTIMANA'), findsOneWidget);

    // "Formazione" apre la formazione.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
    );
    await tester.pumpAndSettle();
    final lineup = find.widgetWithText(OutlinedButton, 'Formazione');
    await tester.ensureVisible(lineup);
    await tester.pumpAndSettle();
    await tester.tap(lineup);
    await tester.pumpAndSettle();
    expect(find.text('FORMAZIONE'), findsOneWidget);
  });

  testWidgets('Home: dopo le 18:30 le risposte sono chiuse', (tester) async {
    await startAppAt(tester, todayInItalyAt(18, 31));
    expect(find.textContaining('Risposte chiuse alle 18:30'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Presente'),
    );
    expect(button.onPressed, isNull);
  });
}
