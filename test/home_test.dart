import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/clock.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/presenze/evening.dart';
import 'package:milanac/main.dart';

/// Avvia l'app demo con l'orologio fermo a [now].
Future<ProviderContainer> startAppAt(WidgetTester tester, DateTime now) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [clockProvider.overrideWithValue(() => now)],
  );
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

DateTime todayAt(int hour, [int minute = 0]) {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day, hour, minute);
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('serata: primo evento del giorno della squadra, altrimenti allenamento '
      '21:30', () {
    final day = DateTime(2026, 10, 3);
    final fallback = eveningEvent(const [], day);
    expect(fallback.type, EventType.allenamento);
    expect(fallback.startsAt, DateTime(2026, 10, 3, 21, 30));

    final partita = ClubEvent(
      id: 'p',
      type: EventType.amichevole,
      title: 'Amichevole',
      startsAt: DateTime(2026, 10, 3, 22),
    );
    final riunione = ClubEvent(
      id: 'r',
      type: EventType.riunione,
      title: 'Riunione',
      startsAt: DateTime(2026, 10, 3, 20),
    );
    final domani = ClubEvent(
      id: 'd',
      type: EventType.amichevole,
      title: 'Domani',
      startsAt: DateTime(2026, 10, 4, 21),
    );
    final futuro = ClubEvent(
      id: 'f',
      team: Team.futuro,
      type: EventType.torneo,
      title: 'Coppa Futuro',
      startsAt: DateTime(2026, 10, 3, 21),
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

  test('risposte aperte fino alle 18:30, anche per i giorni successivi', () {
    final day = DateTime(2026, 10, 3);
    expect(answersOpen(day, DateTime(2026, 10, 3, 18, 29)), isTrue);
    expect(answersOpen(day, DateTime(2026, 10, 3, 18, 30)), isFalse);
    expect(answersOpen(day, DateTime(2026, 10, 2, 23)), isTrue);
    expect(answersOpen(day, DateTime(2026, 10, 4, 9)), isFalse);
  });

  testWidgets('Home: i due riquadri e la risposta per stasera', (tester) async {
    await startAppAt(tester, todayAt(17));

    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    expect(find.text('MONDO PROCLUB'), findsOneWidget);
    expect(find.text('PRESENZE'), findsOneWidget);
    expect(find.text('La build da attaccante più forte'), findsOneWidget);
    expect(find.textContaining('Nuovo aggiornamento FC 27'), findsOneWidget);
    expect(find.textContaining('Aggiornamento PlayStation'), findsOneWidget);
    expect(find.text('ALLENAMENTO · 21:30'), findsOneWidget);
    expect(
      find.text('Ci sei stasera? Rispondi entro le 18:30.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('La tua risposta: Presente'), findsOneWidget);
  });

  testWidgets('Home: dopo le 18:30 le risposte sono chiuse', (tester) async {
    await startAppAt(tester, todayAt(18, 31));
    expect(find.textContaining('Risposte chiuse alle 18:30'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Presente'),
    );
    expect(button.onPressed, isNull);
  });
}
