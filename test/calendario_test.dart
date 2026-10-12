import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/calendario/calendario_page.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/calendario/events_repository.dart';
import 'package:milanac/shared/ui.dart';

import 'helpers.dart';
import 'home_test.dart' show italyAt, startAppAt;

/// Come lo stream del server senza `ascending: true`: gli eventi arrivano dal più lontano.
class _FarthestFirst extends DemoEventsRepository {
  _FarthestFirst({super.now});

  @override
  Stream<List<ClubEvent>> watchAll() =>
      super.watchAll().map((events) => events.reversed.toList());
}

ClubEvent _event(String title, DateTime startsAt) => ClubEvent(
  id: title,
  type: EventType.amichevole,
  title: title,
  startsAt: startsAt,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('prossimi appuntamenti: i cinque più vicini, in qualunque ordine '
      'arrivino', () {
    // Lunedì 12 ottobre 2026, 17:00 italiane.
    final now = italyAt(2026, 10, 12, 17);
    final farthestFirst = [
      for (var day = 30; day >= 13; day -= 3)
        _event('Il $day', DateTime.utc(2026, 10, day, 21, 30)),
      _event('Stasera', DateTime.utc(2026, 10, 12, 21, 30)),
      _event('Ieri', DateTime.utc(2026, 10, 11, 21, 30)),
    ];
    expect(
      [for (final e in upcomingEvents(farthestFirst, now)) e.title],
      ['Stasera', 'Il 15', 'Il 18', 'Il 21', 'Il 24'],
    );
    // Gli orari sono italiani: alle 21:45 di stasera l'evento delle 21:30 è passato.
    expect(
      upcomingEvents(farthestFirst, italyAt(2026, 10, 12, 21, 45)).first.title,
      'Il 15',
    );
  });

  testWidgets('Calendario: questa settimana e più avanti dal più vicino, anche '
      'se gli eventi arrivano dal più lontano', (tester) async {
    final now = italyAt(2026, 10, 12, 17);
    final events = _FarthestFirst(now: now);
    // Più avanti gli appuntamenti sono più di cinque: si vedono i cinque più vicini.
    for (final (title, startsAt) in [
      ('Amichevole lontana', DateTime.utc(2026, 11, 20, 21)),
      ('Finale', DateTime.utc(2026, 12, 20, 21)),
      ('Coppa di gennaio', DateTime.utc(2027, 1, 10, 21)),
      ('Coppa di febbraio', DateTime.utc(2027, 2, 10, 21)),
      ('Coppa di marzo', DateTime.utc(2027, 3, 10, 21)),
    ]) {
      await events.save(_event(title, startsAt));
    }
    await startAppAt(
      tester,
      now,
      overrides: [eventsRepositoryProvider.overrideWithValue(events)],
    );
    // Schermo alto: tutta la lista resta costruita.
    tester.view.physicalSize = const Size(1080, 7200);
    await tester.pumpAndSettle();
    await goToSection(tester, 'Calendario');
    final page = find.byType(CalendarioPage);
    Finder inPage(Finder f) => find.descendant(of: page, matching: f);
    expect(
      inPage(
        find.text(
          "Ogni sera c'è l'allenamento alle 21:30. Qui trovi solo ciò che "
          'cambia.',
        ),
      ),
      findsOneWidget,
    );
    List<String> titles() => [
      for (final row in tester.widgetList<EventRow>(
        inPage(find.byType(EventRow)),
      ))
        row.event.title,
    ];

    await tester.tap(inPage(find.widgetWithText(FilterPill, 'Tutte')));
    await tester.pumpAndSettle();
    expect(titles(), [
      // Questa settimana.
      'FVPA – 3ª giornata vs Atletico Virtuale',
      'Allenamento schemi calci piazzati',
      'Amichevole vs Real Brianza',
      // Più avanti.
      'Riunione direttivo – mercato',
      'Amichevole lontana',
      'Finale',
      'Coppa di gennaio',
      'Coppa di febbraio',
    ]);
    // La partita ufficiale porta alla formazione.
    expect(inPage(find.text('Vedi formazione')), findsOneWidget);

    // Solo il Milan AC: l'amichevole del Futuro non c'è.
    await tester.tap(inPage(find.widgetWithText(FilterPill, 'Milan AC')));
    await tester.pumpAndSettle();
    expect(titles(), isNot(contains('Amichevole vs Real Brianza')));
    expect(titles(), contains('Allenamento schemi calci piazzati'));
  });
}
