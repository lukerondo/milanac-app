import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/errors.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/carte/assign_cards_sheet.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';
import 'package:milanac/features/risultati/match.dart';

/// L'amichevole del Futuro della demo (Real Brianza 2–2).
final _brianza = ClubMatch(
  id: 'm2',
  kind: MatchKind.amichevole,
  team: Team.futuro,
  opponent: 'Real Brianza',
  playedAt: DateTime(2026, 10, 3, 21, 30),
  home: false,
  goalsFor: 2,
  goalsAgainst: 2,
);

/// Carte che arrivano quando lo decide il test; registra l'ultima assegnazione.
class _SlowCards extends DemoSpecialCardsRepository {
  final cards = StreamController<List<SpecialCard>>();
  List<CardAward>? assigned;

  @override
  Stream<List<SpecialCard>> watchAll() => cards.stream;

  @override
  Future<int> assign(ClubMatch match, List<CardAward> awards) async {
    assigned = awards;
    return 0;
  }
}

/// Il menu a tendina con l'etichetta [label].
Finder _picker(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
);

/// Una pagina con il pulsante che apre l'assegnazione delle carte di [match].
Future<void> _openSheet(
  WidgetTester tester,
  ClubMatch match, {
  SpecialCardsRepository? repo,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) specialCardsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showAssignCardsSheet(c, match),
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Apri'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('carte valide: il prossimo cambio è la scadenza (o l\'inizio) più vicina', () {
    final now = DateTime(2026, 10, 10, 17);
    SpecialCard card(String id, int startH, int endH) => SpecialCard(
      id: id,
      playerId: 'p$id',
      kind: CardSpecial.neroOro,
      reparto: 'ATT',
      startsAt: now.add(Duration(hours: startH)),
      endsAt: now.add(Duration(hours: endH)),
    );
    final expired = card('a', -200, -30);
    final active = card('b', -50, 118);
    final soon = card('c', -100, 68);
    final future = card('d', 3, 171);
    expect(nextSpecialCardChange([expired], now), isNull);
    expect(
      nextSpecialCardChange([expired, active, soon], now),
      now.add(const Duration(hours: 68)),
    );
    expect(
      nextSpecialCardChange([active, soon, future], now),
      now.add(const Duration(hours: 3)),
    );
    // Alla scadenza la carta non vale più.
    final at = nextSpecialCardChange([soon], now)!;
    expect(activeSpecialCards([soon], at).containsKey('pc'), isFalse);
    expect(
      activeSpecialCards([soon], at.subtract(const Duration(seconds: 1))),
      contains('pc'),
    );
  });

  test('assegnazione (demo come il server): un giocatore, una carta; '
      'il cambio di reparto dà una carta nuova', () async {
    final repo = DemoSpecialCardsRepository();
    addTearDown(repo.dispose);
    await expectLater(
      repo.assign(_brianza, const [
        CardAward(playerId: 'p6', reparto: 'CEN'),
        CardAward(playerId: 'p6', reparto: 'ATT'),
      ]),
      throwsA(
        isA<AppError>().having(
          (e) => friendlyError(e),
          'messaggio',
          'Un giocatore riceve una sola carta nero/oro',
        ),
      ),
    );
    await expectLater(
      repo.assign(_brianza, const [
        CardAward(playerId: 'p6', reparto: 'CEN'),
        CardAward(playerId: 'p4', reparto: 'CEN'),
      ]),
      throwsA(isA<AppError>()),
    );

    expect(
      await repo.assign(_brianza, const [
        CardAward(playerId: 'p6', reparto: 'CEN', bonus: 3),
        CardAward(playerId: 'p4', reparto: 'POR'),
      ]),
      2,
    );
    // Solo il bonus cambia: la carta resta quella.
    expect(
      await repo.assign(_brianza, const [
        CardAward(playerId: 'p6', reparto: 'CEN', bonus: 5),
        CardAward(playerId: 'p4', reparto: 'POR'),
      ]),
      0,
    );
    // Scambio di reparto: due carte nuove, le vecchie spariscono.
    expect(
      await repo.assign(_brianza, const [
        CardAward(playerId: 'p6', reparto: 'POR'),
        CardAward(playerId: 'p4', reparto: 'CEN'),
      ]),
      2,
    );
    final mine = (await repo.watchAll().first)
        .where((c) => c.matchId == 'm2')
        .map((c) => '${c.playerId}:${c.reparto}')
        .toSet();
    expect(mine, {'p6:POR', 'p4:CEN'});
  });

  testWidgets('Assegnazione: le carte già date si leggono solo quando arrivano '
      '(prima il salvataggio le cancellava)', (tester) async {
    final repo = _SlowCards();
    await _openSheet(tester, _brianza, repo: repo);
    // Carte non ancora arrivate: niente modulo, niente salvataggio.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Assegna le carte'), findsNothing);

    final now = DateTime.now();
    repo.cards.add([
      SpecialCard(
        id: 'x1',
        playerId: 'p6',
        kind: CardSpecial.neroOro,
        reparto: 'CEN',
        bonus: 3,
        matchId: 'm2',
        team: Team.futuro,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 6)),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Paolo Verdi (CC)'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);

    await tester.ensureVisible(find.text('Assegna le carte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assegna le carte'));
    await tester.pumpAndSettle();
    expect(repo.assigned, hasLength(1));
    expect(repo.assigned!.single.playerId, 'p6');
    expect(repo.assigned!.single.reparto, 'CEN');
    expect(repo.assigned!.single.bonus, 3);
  });

  testWidgets('Assegnazione: chi ha già la carta in un reparto non si sceglie '
      'in un altro', (tester) async {
    await _openSheet(tester, _brianza);
    await tester.pumpAndSettle();

    await tester.tap(_picker('CEN · Centrocampo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paolo Verdi (CC)').last);
    await tester.pumpAndSettle();

    // Nel menu dell'attacco Verdi c'è, ma spento e con il motivo.
    await tester.tap(_picker('ATT · Attacco'));
    await tester.pumpAndSettle();
    final taken = find.text('Paolo Verdi (CC) · ha già la carta CEN');
    expect(taken, findsOneWidget);
    final item = tester.widget<DropdownMenuItem<String?>>(
      find.ancestor(
        of: taken,
        matching: find.byWidgetPredicate((w) => w is DropdownMenuItem),
      ),
    );
    expect(item.enabled, isFalse);
    await tester.tap(taken, warnIfMissed: false);
    await tester.pumpAndSettle();
    // Il menu resta aperto: si chiude scegliendo "Nessuno".
    await tester.tap(find.text('Nessuno').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Assegna le carte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assegna le carte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carte assegnate: 1 nuove'), findsOneWidget);
  });
}
