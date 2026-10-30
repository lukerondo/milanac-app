import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/risultati/match.dart';
import 'package:milanac/features/risultati/matches_repository.dart';
import 'package:milanac/features/risultati/result_poster.dart';
import 'package:milanac/features/rosa/member.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayAt;

/// Registra le condivisioni chieste al telefono (share_plus) e fa trovare una cartella
/// temporanea a chi deve salvare l'immagine prima di condividerla.
List<MethodCall> _recordShares(WidgetTester tester) {
  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(share, (call) async {
    calls.add(call);
    return 'dev.fluttercommunity.plus/share/success';
  });
  messenger.setMockMethodCallHandler(
    paths,
    (call) async => Directory.systemTemp.path,
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(share, null);
    messenger.setMockMethodCallHandler(paths, null);
  });
  return calls;
}

Future<void> _openPoster(WidgetTester tester, String opponent) async {
  await goToSection(tester, 'Risultati');
  await tester.tap(find.text(opponent));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Condividi'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('Testo del risultato: punteggio, giornata, marcatori con i minuti', () {
    Member player(String id, String name) => Member(
      id: id,
      displayName: name,
      role: ClubRole.giocatore,
      joinedAt: DateTime(2025),
    );
    final match = ClubMatch(
      id: 'x',
      kind: MatchKind.torneo,
      competition: 'FVPA Serie B – 2ª giornata',
      opponent: 'Dinamo Pixel',
      playedAt: DateTime.utc(2026, 10, 25, 21, 30),
      goalsFor: 3,
      goalsAgainst: 1,
      scorers: 'Rossi (2), Bianchi',
      timeline: const [
        MatchGoal(minute: 18, ours: false),
        MatchGoal(minute: 52, ours: true, scorer: 'Rossi'),
        MatchGoal(minute: 67, ours: true, scorer: 'Rossi'),
        MatchGoal(minute: 88, ours: true, scorer: 'Bianchi'),
      ],
    );
    expect(
      resultShareText(match, [
        player('p2', 'Marco Rossi'),
        player('p3', 'Luca Bianchi'),
      ]),
      'Milan AC 3 – 1 Dinamo Pixel\n'
      'FVPA Serie B · 2ª giornata\n'
      "Marcatori: Rossi 52' 67', Bianchi 88'\n"
      "Gol Dinamo Pixel: 18'\n"
      'MILANAC Pro Club',
    );
    // Da giocare: solo le squadre e la giornata.
    final soon = ClubMatch(
      id: 'y',
      kind: MatchKind.amichevole,
      opponent: 'Lupi',
      playedAt: DateTime.utc(2026, 11, 2, 21, 30),
      home: false,
    );
    expect(
      resultShareText(soon, const []),
      'Milan AC – Lupi\nAmichevole · in trasferta\nMILANAC Pro Club',
    );
  });

  testWidgets('Grafica del risultato: anteprima del poster, condivisione come '
      'immagine e come testo', (tester) async {
    final shares = _recordShares(tester);
    await startAppAt(tester, todayAt(17));
    await _openPoster(tester, 'Dinamo Pixel');

    expect(find.text('CONDIVIDI IL RISULTATO'), findsOneWidget);
    expect(find.byType(ResultPoster), findsOneWidget);
    expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    expect(find.text('VITTORIA'), findsOneWidget);
    expect(find.text("Rossi 52' 67'"), findsOneWidget);
    expect(find.text("Bianchi 88'"), findsOneWidget);
    expect(find.text("18'"), findsOneWidget);
    expect(find.text('CARTE DELLA GIORNATA'), findsOneWidget);
    expect(find.text('Rossi ATT +5'), findsOneWidget);
    expect(find.text('Neri POR +5'), findsOneWidget);
    expect(find.text('«Rimonta nel secondo tempo!»'), findsOneWidget);
    expect(find.text('MILANO SIAMO NOI'), findsOneWidget);

    // L'immagine: un PNG passato al foglio di condivisione del telefono.
    await tester.runAsync(() async {
      await tester.tap(find.text("Condividi l'immagine"));
      for (var i = 0; i < 20 && shares.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
    expect(shares, hasLength(1));
    final image = shares.single.arguments as Map;
    expect(image['text'], 'Milan AC 3 – 1 Dinamo Pixel · MILANAC Pro Club');
    expect((image['uris'] ?? image['paths'] ?? image['files']), isNotNull);
    expect(find.text('Condivisione non riuscita'), findsNothing);

    // Il testo.
    await tester.tap(find.text('Condividi come testo'));
    await tester.pumpAndSettle();
    expect(shares, hasLength(2));
    expect(
      (shares.last.arguments as Map)['text'],
      contains("Marcatori: Rossi 52' 67', Bianchi 88'"),
    );
  });

  testWidgets('Partita da giocare: il poster mostra VS, senza esito', (
    tester,
  ) async {
    final container = await startAppAt(tester, todayAt(17));
    final id = await container
        .read(matchesRepositoryProvider)
        .save(
          ClubMatch(
            id: '',
            kind: MatchKind.amichevole,
            opponent: 'Lupi Grigi',
            playedAt: DateTime.utc(2026, 12, 1, 21, 30),
          ),
        );
    container.read(routerProvider).go('/partita/$id');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Condividi'));
    await tester.pumpAndSettle();
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('LUPI GRIGI'), findsOneWidget);
    for (final outcome in ['VITTORIA', 'PAREGGIO', 'SCONFITTA']) {
      expect(find.text(outcome), findsNothing);
    }
    expect(find.text('CARTE DELLA GIORNATA'), findsNothing);
  });
}
