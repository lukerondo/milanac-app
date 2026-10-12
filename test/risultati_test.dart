import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/italian_time.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/features/risultati/match_detail_page.dart';
import 'package:milanac/features/risultati/match_editor.dart';
import 'package:milanac/features/risultati/matches_repository.dart';
import 'package:milanac/features/risultati/risultati_page.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;

/// Partite che arrivano quando lo decide il test (come una rete lenta).
class _SlowMatches extends DemoMatchesRepository {
  final streams = <StreamController<List<ClubMatch>>>[];

  @override
  Stream<List<ClubMatch>> watchAll() {
    final c = StreamController<List<ClubMatch>>();
    streams.add(c);
    return c.stream;
  }
}

/// Conta quanti stream dei media vengono aperti.
class _CountingMatches extends DemoMatchesRepository {
  var mediaStreams = 0;

  @override
  Stream<List<MatchMedia>> watchAllMedia() {
    mediaStreams++;
    return super.watchAllMedia();
  }
}

/// Il tasto indietro della pagina della partita.
final _back = find.descendant(
  of: find.byType(MatchDetailPage),
  matching: find.byType(BackButton),
);

Future<ProviderContainer> _startApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: overrides);
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

  test('partite in ora italiana, come gli eventi', () {
    // Le 21:30 italiane del 12 ottobre (ora legale): le 19:30 UTC.
    final summer = ClubMatch.fromMap({
      'id': 'a',
      'kind': 'torneo',
      'opponent': 'Dinamo Pixel',
      'played_at': '2026-10-12T19:30:00+00:00',
      'created_at': '2026-10-12T21:45:10+00:00',
    });
    expect(summer.playedAt, DateTime.utc(2026, 10, 12, 21, 30));
    expect(summer.createdAt, DateTime.utc(2026, 10, 12, 21, 45, 10));
    expect(summer.toMap()['played_at'], '2026-10-12T19:30:00.000Z');
    // D'inverno l'Italia è un'ora avanti a UTC.
    final winter = ClubMatch.fromMap({
      'id': 'b',
      'kind': 'amichevole',
      'opponent': 'Real Brianza',
      'played_at': '2026-12-01T20:30:00Z',
    });
    expect(winter.playedAt, DateTime.utc(2026, 12, 1, 21, 30));
    expect(winter.createdAt, isNull);
    expect(winter.toMap()['played_at'], '2026-12-01T20:30:00.000Z');
  });

  test('due partite nella stessa sera: prima l\'ultima inserita', () {
    ClubMatch match(String id, DateTime playedAt, [DateTime? createdAt]) =>
        ClubMatch(
          id: id,
          kind: MatchKind.amichevole,
          opponent: id,
          playedAt: playedAt,
          createdAt: createdAt,
        );
    final evening = DateTime.utc(2026, 10, 12, 21, 30);
    final first = match('b', evening, DateTime.utc(2026, 10, 12, 20, 40));
    final second = match('a', evening, DateTime.utc(2026, 10, 12, 21, 50));
    // Inserita dopo, ma giocata il giorno prima.
    final dayBefore = match(
      'z',
      evening.subtract(const Duration(days: 1)),
      DateTime.utc(2026, 10, 13),
    );
    expect(
      [
        for (final m in [first, dayBefore, second]..sort(newestMatchFirst))
          m.id,
      ],
      ['a', 'b', 'z'],
    );
    // Stesso orario e stesso inserimento: decide l'id, come sul server.
    expect(
      ([
        match('a', evening),
        match('b', evening),
      ]..sort(newestMatchFirst)).first.id,
      'b',
    );
  });

  testWidgets('Due partite nella stessa sera: l\'ultima inserita è l\'ultimo '
      'risultato in Home, Calendario e Risultati', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(23, 30));
    await goToSection(tester, 'Risultati');
    for (final (opponent, goalsFor, goalsAgainst) in [
      ('Primo', '2', '0'),
      ('Secondo', '1', '1'),
    ]) {
      await tester.tap(find.text('Nuova partita'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Avversario'),
        opponent,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'MILAN AC'),
        goalsFor,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Avversari'),
        goalsAgainst,
      );
      await tester.ensureVisible(find.text('Salva partita'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva partita'));
      await tester.pumpAndSettle();
    }

    // Tutte e due alle 21:30 italiane di oggi.
    final today = italianClock(todayInItalyAt(23, 30));
    final evening = DateTime.utc(today.year, today.month, today.day, 21, 30);
    final saved = container.read(matchesProvider).value!;
    expect([for (final m in saved.take(2)) m.opponent], ['Secondo', 'Primo']);
    expect([for (final m in saved.take(2)) m.playedAt], [evening, evening]);

    // Risultati.
    expect(
      tester.widgetList<MatchRow>(find.byType(MatchRow)).first.match.opponent,
      'Secondo',
    );

    // Calendario: "Ultimi risultati".
    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Primo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getTopLeft(find.text('Secondo')).dy,
      lessThan(tester.getTopLeft(find.text('Primo')).dy),
    );

    // Home: l'ultimo risultato è il pareggio con il Secondo.
    await tapTab(tester, 'Home');
    await tester.scrollUntilVisible(
      find.textContaining('ULTIMO RISULTATO'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SECONDO'), findsOneWidget);
    expect(find.text('PRIMO'), findsNothing);
    expect(find.text('1 – 1'), findsOneWidget);
  });

  test('risultato: tutti e due i punteggi o nessuno', () {
    expect(resultError(null, null), isNull);
    expect(resultError(2, 1), isNull);
    expect(resultError(0, 0), isNull);
    expect(resultError(2, null), contains('entrambi i punteggi'));
    expect(resultError(null, 0), contains('entrambi i punteggi'));
  });

  testWidgets('Dettaglio partita: spinner finché le partite non arrivano, '
      '"non trovata" solo con l\'elenco caricato', (tester) async {
    final repo = _SlowMatches();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matchesRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: MatchDetailPage(matchId: 'm9')),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Partita non trovata.'), findsNothing);

    // L'elenco arriva senza quella partita (eliminata): ora lo si dice, con Riprova.
    repo.streams.last.add(const []);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Partita non trovata.'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    // Riprova ricarica l'elenco (spinner) e la partita compare.
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(repo.streams, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Partita non trovata.'), findsNothing);
    repo.streams.last.add([
      ClubMatch(
        id: 'm9',
        kind: MatchKind.amichevole,
        opponent: 'Atletico Joystick',
        playedAt: DateTime(2026, 10, 1, 21, 30),
        goalsFor: 2,
        goalsAgainst: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'PARTITA'), findsOneWidget);
    expect(find.text('ATLETICO JOYSTICK'), findsOneWidget);
    expect(find.text('2 – 1'), findsOneWidget);
  });

  testWidgets('Risultati: un solo stream dei media per tutte le schede, '
      'e le eliminazioni arrivano', (tester) async {
    final repo = _CountingMatches();
    await _startApp(
      tester,
      overrides: [matchesRepositoryProvider.overrideWithValue(repo)],
    );
    await goToSection(tester, 'Risultati');
    expect(find.byType(MatchRow), findsNWidgets(3));
    expect(repo.mediaStreams, 1);
    // Solo la 2ª giornata ha un contenuto (il link agli highlights).
    expect(find.byIcon(Icons.play_circle_rounded), findsOneWidget);

    await tester.tap(find.text('Dinamo Pixel'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Highlights completi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Highlights completi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nessun video o foto per questa partita.'),
      findsOneWidget,
    );

    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_circle_rounded), findsNothing);
    expect(repo.mediaStreams, 1);
  });

  testWidgets('Partita aperta da una notifica: indietro porta ai Risultati', (
    tester,
  ) async {
    final container = await _startApp(tester);
    final router = container.read(routerProvider);

    // La notifica apre la partita come unica pagina.
    router.go('/partita/m1');
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailPage), findsOneWidget);
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailPage), findsNothing);
    expect(find.byType(RisultatiPage), findsOneWidget);

    // Anche il tasto indietro di Android porta ai Risultati invece di chiudere l'app.
    router.go('/partita/m1');
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailPage), findsNothing);
    expect(find.byType(RisultatiPage), findsOneWidget);

    // Aperta dall'elenco, indietro torna semplicemente all'elenco.
    await tester.tap(find.text('Dinamo Pixel'));
    await tester.pumpAndSettle();
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailPage), findsNothing);
    expect(find.byType(RisultatiPage), findsOneWidget);
  });

  testWidgets('Nuova partita: un solo punteggio non si salva', (tester) async {
    final container = await _startApp(tester);
    await goToSection(tester, 'Risultati');
    await tester.tap(find.text('Nuova partita'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Avversario'),
      'Atletico Joystick',
    );
    await tester.enterText(find.widgetWithText(TextField, 'MILAN AC'), '2');
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Inserisci entrambi i punteggi'),
      findsOneWidget,
    );
    expect(
      container.read(matchesProvider).value!.map((m) => m.opponent),
      isNot(contains('Atletico Joystick')),
    );
    // Il messaggio sparisce da solo.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Con tutti e due i punteggi la partita si salva (giocata).
    await tester.enterText(find.widgetWithText(TextField, 'Avversari'), '0');
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();
    final saved = container
        .read(matchesProvider)
        .value!
        .firstWhere((m) => m.opponent == 'Atletico Joystick');
    expect(saved.outcome, MatchOutcome.vittoria);
  });
}
