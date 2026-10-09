import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<void> open(WidgetTester tester, String section) async {
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
  await goToSection(tester, section);
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('youtubeId', () {
    test('riconosce i formati comuni', () {
      expect(youtubeId('https://www.youtube.com/watch?v=abc123'), 'abc123');
      expect(youtubeId('https://youtu.be/abc123'), 'abc123');
      expect(youtubeId('https://youtube.com/shorts/abc123'), 'abc123');
      expect(youtubeId('https://www.twitch.tv/milanac'), isNull);
    });
  });

  test('bilancio partite', () {
    final d = DateTime(2026);
    final r = MatchRecord([
      ClubMatch(
        id: '1',
        kind: MatchKind.torneo,
        opponent: 'A',
        playedAt: d,
        goalsFor: 3,
        goalsAgainst: 1,
      ),
      ClubMatch(
        id: '2',
        kind: MatchKind.torneo,
        opponent: 'B',
        playedAt: d,
        goalsFor: 1,
        goalsAgainst: 1,
      ),
      ClubMatch(id: '3', kind: MatchKind.torneo, opponent: 'C', playedAt: d),
    ]);
    expect(
      (r.played, r.wins, r.draws, r.losses, r.goalsFor, r.goalsAgainst),
      (2, 1, 1, 0, 4, 2),
    );
  });

  testWidgets('Calendario: il Direttivo crea un evento', (tester) async {
    await open(tester, 'Calendario');
    expect(find.text('PROSSIMI APPUNTAMENTI'), findsOneWidget);

    await tester.tap(find.text('Nuovo evento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allenamento').last);
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Allenamento difesa',
    );
    await tester.ensureVisible(find.text('Salva evento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva evento'));
    await tester.pumpAndSettle();

    expect(find.text('Allenamento difesa'), findsWidgets);
  });

  testWidgets('Risultati: nuova partita e link agli highlights', (
    tester,
  ) async {
    await open(tester, 'Risultati');
    expect(find.text('Dinamo Pixel'), findsOneWidget);

    await tester.tap(find.text('Nuova partita'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Avversario'),
      'Inter Digitale',
    );
    await tester.enterText(find.widgetWithText(TextField, 'MILAN AC'), '4');
    await tester.enterText(find.widgetWithText(TextField, 'Avversari'), '0');
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();

    expect(find.text('Inter Digitale'), findsOneWidget);
    expect(find.text('4 : 0'), findsOneWidget);

    // Apre la partita e aggiunge un link.
    await tester.tap(find.text('Inter Digitale'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nessun video o foto per questa partita.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Aggiungi media'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link a un video'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'youtu.be/xyz',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Descrizione (facoltativa)'),
      'Poker!',
    );
    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(find.text('Poker!'), findsOneWidget);
  });
}
