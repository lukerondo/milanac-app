import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/italian_time.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/calendario/events_repository.dart';

import 'home_test.dart' show startAppAt, todayInItalyAt;

/// Mette in calendario la partita di oggi alle [hour]:[minute] italiane.
Future<void> _matchToday(
  ProviderContainer container,
  DateTime now, {
  int hour = 21,
  int minute = 30,
}) async {
  final today = italianClock(now);
  await container
      .read(eventsRepositoryProvider)
      .save(
        ClubEvent(
          id: '',
          type: EventType.torneo,
          title: 'FVPA Serie B – 4ª giornata vs Lupi Grigi',
          startsAt: DateTime.utc(
            today.year,
            today.month,
            today.day,
            hour,
            minute,
          ),
        ),
      );
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('Codice del party: letto, salvato solo se c\'è, tenuto modificando', () {
    final e = ClubEvent.fromMap({
      'id': 'x',
      'type': 'torneo',
      'title': 'vs Lupi',
      'starts_at': '2026-10-30T20:30:00+00:00',
      'party_code': 'MILANAC21',
    });
    expect(e.partyCode, 'MILANAC21');
    expect(e.toMap()['party_code'], 'MILANAC21');
    expect(e.withPartyCode(null).toMap().containsKey('party_code'), isFalse);
  });

  testWidgets('Match Day: conto alla rovescia, chi è pronto, formazione e '
      'codice del party', (tester) async {
    var now = todayInItalyAt(18, 54);
    final container = await startAppAt(tester, now, clock: () => now);
    await _matchToday(container, now);
    await tester.pumpAndSettle();

    expect(find.text('MATCH DAY · MILAN AC'), findsOneWidget);
    expect(find.text('LUPI GRIGI'), findsOneWidget);
    expect(find.text("al calcio d'inizio · 21:30"), findsOneWidget);
    for (final digits in ['02', '36', '00']) {
      expect(find.text(digits), findsOneWidget);
    }
    // Un secondo dopo il tabellone scorre.
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('35'), findsOneWidget);
    expect(find.text('59'), findsOneWidget);

    // La partita di stasera non si ripete in "Prossima partita".
    expect(find.text('MILAN AC – LUPI GRIGI'), findsNothing);
    expect(find.text('PRONTI'), findsOneWidget);
    expect(find.text('La formazione non è ancora pubblicata'), findsOneWidget);

    // Il Direttivo scrive il codice del party; tutti lo copiano.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.ensureVisible(find.text('Scrivi il codice del party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrivi il codice del party'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  MILANAC21 ');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Party: MILANAC21'), findsOneWidget);
    await tester.tap(find.byTooltip('Copia il codice'));
    await tester.pumpAndSettle();
    expect(copied, ['MILANAC21']);
    expect(find.text('Codice del party copiato.'), findsOneWidget);
  });

  testWidgets("Match Day: in corso dal calcio d'inizio", (tester) async {
    final now = todayInItalyAt(21, 45);
    final container = await startAppAt(tester, now);
    await _matchToday(container, now);
    await tester.pumpAndSettle();
    expect(find.text('IN CORSO'), findsOneWidget);
    expect(find.text(' · dalle 21:30'), findsOneWidget);
  });

  testWidgets('Match Day: dopo la partita il fischio finale', (tester) async {
    // Partita delle 18: alle 21:45 è finita da un pezzo.
    final now = todayInItalyAt(21, 45);
    final container = await startAppAt(tester, now);
    await _matchToday(container, now, hour: 18, minute: 0);
    await tester.pumpAndSettle();
    expect(
      find.text('Fischio finale: il risultato lo inserisce il Direttivo.'),
      findsOneWidget,
    );
  });

  testWidgets('Senza partita stasera la card resta "Stasera"', (tester) async {
    await startAppAt(tester, todayInItalyAt(17));
    expect(find.textContaining('MATCH DAY'), findsNothing);
    expect(find.textContaining('STASERA'), findsOneWidget);
  });
}
