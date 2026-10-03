import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/news/tonight_panel.dart';
import 'package:milanac/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('stasera: primo evento del giorno, altrimenti allenamento 21:30', () {
    final now = DateTime(2026, 10, 3, 12);
    final fallback = tonightEvent(const [], now);
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
    expect(tonightEvent([domani, riunione, partita], now).id, 'p');
  });

  testWidgets('Home: bottone Stasera apre il pannello laterale', (
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

    // La Home mostra le notizie; il riepilogo della serata è dietro al bottone tondo.
    expect(find.text('Notizie dal mondo FC'), findsOneWidget);
    expect(find.textContaining('STASERA ·'), findsNothing);

    await tester.tap(find.byTooltip('Stasera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('STASERA ·'), findsOneWidget);
    expect(find.text('Presenti'), findsOneWidget);
    expect(find.text('Ritardi'), findsOneWidget);
    expect(find.text('Assenti'), findsOneWidget);
    expect(find.text('non ancora pubblicata'), findsOneWidget);
    expect(find.text('Ci sei stasera?'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(TonightPanel),
        matching: find.widgetWithText(OutlinedButton, 'Presente'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Presente alle 21:30'), findsOneWidget);

    await tester.tap(find.byTooltip('Chiudi').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('STASERA ·'), findsNothing);
  });
}
