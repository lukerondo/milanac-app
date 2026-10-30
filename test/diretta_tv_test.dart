import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/features/risultati/match_tv.dart';
import 'package:milanac/features/risultati/matches_repository.dart';
import 'package:milanac/features/risultati/media_viewer.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'helpers.dart';

/// Server prima della migrazione 0027: le partite si salvano senza minuti.
class _NoTimeline extends DemoMatchesRepository {
  @override
  bool get timelineMissing => true;
}

/// Una foto vera (1×1), come quelle caricate dalla galleria.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
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

Future<void> _openMatch(WidgetTester tester, String opponent) async {
  await goToSection(tester, 'Risultati');
  await tester.tap(find.text(opponent));
  await tester.pumpAndSettle();
}

/// Il minuto scritto in un campo dell'editor.
String _minute(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test(
    'Minuti dei gol: lettura, scrittura, ordine e punteggio dopo ogni gol',
    () {
      final m = ClubMatch.fromMap({
        'id': 'a',
        'kind': 'torneo',
        'opponent': 'Lupi',
        'played_at': '2026-10-12T19:30:00+00:00',
        'goals_for': 2,
        'goals_against': 1,
        'timeline': [
          {'minute': 67, 'side': 'us', 'scorer': 'Rossi'},
          {'minute': 18, 'side': 'them', 'scorer': 'ignorato'},
          {'minute': 'x', 'side': 'us'},
          {'minute': 30, 'side': 'noi'},
          {'minute': 0, 'side': 'us'},
          {'minute': 52, 'side': 'us', 'scorer': '  '},
        ],
      });
      expect(m.timeline, const [
        MatchGoal(minute: 18, ours: false),
        MatchGoal(minute: 52, ours: true),
        MatchGoal(minute: 67, ours: true, scorer: 'Rossi'),
      ]);
      expect(runningScore(m.timeline), [(0, 1), (1, 1), (2, 1)]);
      expect(m.toMap()['timeline'], [
        {'minute': 18, 'side': 'them'},
        {'minute': 52, 'side': 'us'},
        {'minute': 67, 'side': 'us', 'scorer': 'Rossi'},
      ]);
      // Le partite lette da un server prima della 0027 non hanno minuti.
      final old = ClubMatch.fromMap({
        'id': 'b',
        'kind': 'amichevole',
        'opponent': 'Lupi',
        'played_at': '2026-10-12T19:30:00+00:00',
      });
      expect(old.timeline, isEmpty);
      // A pari minuto resta l'ordine in cui sono scritti.
      expect(
        sortedGoals(const [
          MatchGoal(minute: 90, ours: true, scorer: 'B'),
          MatchGoal(minute: 90, ours: false),
          MatchGoal(minute: 10, ours: true, scorer: 'A'),
        ]).map((g) => g.scorer),
        ['A', 'B', null],
      );
    },
  );

  test(
    'Tabellone: marcatori per cognome con i minuti; i gol senza minuto in coda',
    () {
      Member player(String id, String name) => Member(
        id: id,
        displayName: name,
        role: ClubRole.giocatore,
        joinedAt: DateTime(2025),
      );
      final match = ClubMatch(
        id: 'x',
        kind: MatchKind.amichevole,
        opponent: 'Lupi',
        playedAt: DateTime.utc(2026, 10, 1, 21, 30),
        goalsFor: 6,
        goalsAgainst: 0,
        scorers: 'Rossi (2), Neri (2), Gialli (2)',
        timeline: const [
          MatchGoal(minute: 10, ours: true, scorer: 'Rossi'),
          MatchGoal(minute: 20, ours: true, scorer: 'Neri'),
          MatchGoal(minute: 80, ours: true, scorer: 'Rossi'),
        ],
      );
      expect(
        scorerTicker(match, [
          player('p2', 'Marco Rossi'),
          player('p5', 'Andrea Neri'),
        ]),
        ["Rossi 10' 80'", "Neri 20' +1", 'Gialli ×2'],
      );
    },
  );

  test(
    'Server senza la colonna dei minuti: la partita si salva lo stesso',
    () async {
      final sent = <Map<String, dynamic>>[];
      Future<String> write(Map<String, dynamic> map) async {
        sent.add(Map.of(map));
        if (map.containsKey('timeline')) {
          throw PostgrestException(
            message: "Could not find the 'timeline' column of 'matches' in the schema cache",
            code: 'PGRST204',
          );
        }
        return 'id1';
      }

      final (id, missing) = await writeMatch({
        'opponent': 'Lupi',
        'timeline': [
          {'minute': 12, 'side': 'us'},
        ],
      }, write);
      expect(id, 'id1');
      expect(missing, isTrue);
      expect(sent, hasLength(2));
      expect(sent.last.containsKey('timeline'), isFalse);

      // Poi i minuti non si mandano più.
      sent.clear();
      await writeMatch(
        {'opponent': 'Lupi', 'timeline': []},
        write,
        timelineMissing: true,
      );
      expect(sent.single.containsKey('timeline'), isFalse);

      // Gli altri errori arrivano a chi salva.
      await expectLater(
        writeMatch(
          {'timeline': []},
          (_) async =>
              throw PostgrestException(message: 'permesso', code: '42501'),
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  testWidgets('Partita come in diretta: tabellone, cronaca e punteggio dopo '
      'ogni gol', (tester) async {
    await _startApp(tester);
    await _openMatch(tester, 'Dinamo Pixel');

    // Tabellone: le caselle del punteggio, FINALE e i marcatori con i minuti.
    expect(find.text('FINALE'), findsOneWidget);
    expect(find.text("Rossi 52' 67'"), findsOneWidget);
    expect(find.text("Bianchi 88'"), findsOneWidget);
    expect(find.text('MARCATORI'), findsNothing);

    // Cronaca dal calcio d'inizio al fischio finale.
    expect(find.text('CRONACA'), findsOneWidget);
    expect(find.text("Calcio d'inizio"), findsOneWidget);
    expect(find.text('Gol avversario'), findsOneWidget);
    expect(find.text('GOL!'), findsNWidgets(3));
    expect(find.text('Intervallo'), findsOneWidget);
    expect(find.text('Fischio finale'), findsOneWidget);
    for (final score in ['0 – 1', '1 – 1', '2 – 1']) {
      expect(find.text(score), findsOneWidget);
    }
    expect(find.text('3 – 1'), findsNWidgets(2)); // l'ultimo gol e il finale
    expect(find.text('«Rimonta nel secondo tempo!»'), findsOneWidget);
  });

  testWidgets('Senza minuti resta l\'elenco dei marcatori', (tester) async {
    await _startApp(tester);
    await _openMatch(tester, 'Real Brianza');
    expect(find.text('MARCATORI'), findsOneWidget);
    expect(find.text('CRONACA'), findsNothing);
    expect(find.text('FINALE'), findsOneWidget);
  });

  testWidgets('Minuti mancanti: niente punteggio dopo ogni gol (sarebbe '
      'sbagliato)', (tester) async {
    final container = await _startApp(tester);
    final id = await container
        .read(matchesRepositoryProvider)
        .save(
          ClubMatch(
            id: '',
            kind: MatchKind.amichevole,
            opponent: 'Lupi Grigi',
            playedAt: DateTime.utc(2026, 10, 1, 21, 30),
            goalsFor: 2,
            goalsAgainst: 0,
            scorers: 'Rossi, Bianchi',
            timeline: const [
              MatchGoal(minute: 12, ours: true, scorer: 'Rossi'),
            ],
          ),
        );
    container.read(routerProvider).go('/partita/$id');
    await tester.pumpAndSettle();
    expect(find.text("Rossi 12'"), findsOneWidget);
    expect(find.text('Bianchi'), findsOneWidget);
    expect(find.text('GOL!'), findsOneWidget);
    expect(find.text('1 – 0'), findsNothing);
    expect(find.text('2 – 0'), findsOneWidget); // solo il fischio finale
  });

  testWidgets('Editor: un minuto per gol dai marcatori; salvato va nella '
      'cronaca', (tester) async {
    final container = await _startApp(tester);
    await _openMatch(tester, 'Dinamo Pixel');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifica partita'));
    await tester.pumpAndSettle();

    // I nostri nell'ordine dei marcatori, poi quello subito.
    expect(find.text('Minuti dei gol'), findsOneWidget);
    expect(find.text('Gol subito'), findsOneWidget);
    expect(_minute(tester, 'minuto-noi-0'), '52');
    expect(_minute(tester, 'minuto-noi-1'), '67');
    expect(_minute(tester, 'minuto-noi-2'), '88');
    expect(_minute(tester, 'minuto-loro-0'), '18');

    // Bianchi ha segnato al 90'.
    await tester.ensureVisible(find.byKey(const Key('minuto-noi-2')));
    await tester.enterText(find.byKey(const Key('minuto-noi-2')), '90');
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();
    final m1 = container
        .read(matchesProvider)
        .value!
        .firstWhere((m) => m.id == 'm1');
    expect(
      m1.timeline.last,
      const MatchGoal(minute: 90, ours: true, scorer: 'Bianchi'),
    );
    expect(find.text("Bianchi 90'"), findsOneWidget);
  });

  testWidgets('Nuova partita: minuto fuori misura non si salva', (
    tester,
  ) async {
    final container = await _startApp(tester);
    await goToSection(tester, 'Risultati');
    await tester.tap(find.text('Nuova partita'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Avversario'),
      'Atletico Joystick',
    );
    await tester.enterText(find.widgetWithText(TextField, 'MILAN AC'), '2');
    await tester.enterText(find.widgetWithText(TextField, 'Avversari'), '0');
    await tester.enterText(
      find.widgetWithText(TextField, 'Marcatori'),
      'Rossi, Bianchi',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minuto-noi-1')), findsOneWidget);
    expect(find.byKey(const Key('minuto-loro-0')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('minuto-noi-0')));
    await tester.enterText(find.byKey(const Key('minuto-noi-0')), '0');
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Minuto non valido'), findsOneWidget);
    // L'avviso sparisce da solo e lascia di nuovo libero "Salva partita".
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('minuto-noi-0')));
    await tester.enterText(find.byKey(const Key('minuto-noi-0')), '12');
    await tester.enterText(find.byKey(const Key('minuto-noi-1')), '75');
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();
    final saved = container
        .read(matchesProvider)
        .value!
        .firstWhere((m) => m.opponent == 'Atletico Joystick');
    expect(saved.timeline, const [
      MatchGoal(minute: 12, ours: true, scorer: 'Rossi'),
      MatchGoal(minute: 75, ours: true, scorer: 'Bianchi'),
    ]);
  });

  testWidgets('Server non ancora aggiornato: la partita si salva e lo dice', (
    tester,
  ) async {
    await _startApp(
      tester,
      overrides: [matchesRepositoryProvider.overrideWithValue(_NoTimeline())],
    );
    await _openMatch(tester, 'Dinamo Pixel');
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifica partita'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Salva partita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva partita'));
    await tester.pumpAndSettle();
    expect(find.textContaining('I minuti dei gol si vedranno'), findsOneWidget);
  });

  testWidgets('Foto e clip in grande, poi a tutto schermo una dopo l\'altra', (
    tester,
  ) async {
    final container = await _startApp(tester);
    final repo = container.read(matchesRepositoryProvider);
    for (final caption in ['Il gol di Rossi', 'Festa sotto la curva']) {
      await repo.uploadMedia(
        'm3',
        type: MediaType.photo,
        bytes: _pixel,
        extension: 'jpg',
        caption: caption,
      );
    }
    await _openMatch(tester, 'Sporting Joypad');
    await tester.scrollUntilVisible(
      find.text('Il gol di Rossi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('FOTO'), findsWidgets);
    await tester.tap(find.text('Il gol di Rossi'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaGallery), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Festa sotto la curva'), findsOneWidget);
  });
}
