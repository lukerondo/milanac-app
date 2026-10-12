import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/features/carta/card_stats.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/traguardi/achievements.dart';
import 'package:milanac/features/traguardi/player_stats.dart';
import 'package:milanac/features/walkout/celebrations.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<void> startApp(WidgetTester tester) async {
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
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('traguardi: avanzamento e badge più rari', () {
    final member = Member(
      id: 'x',
      displayName: 'Marco Rossi',
      role: ClubRole.giocatore,
      joinedAt: DateTime(2024, 1, 1),
      overall: 86,
    );
    const card = CardStats(
      presence: 80,
      punctuality: 90,
      nights: 20,
      goals: 11,
      months: 21,
      winRate: 60,
    );
    const stats = PlayerStats(presences: 48, cleanMonth: true);
    final list = progressFor(member, card, stats);
    bool unlocked(String id) =>
        list.firstWhere((p) => p.achievement.id == id).unlocked;
    expect(unlocked('presenze_10'), isTrue);
    expect(unlocked('presenze_50'), isFalse);
    expect(list.firstWhere((p) => p.achievement.id == 'presenze_50').value, 48);
    expect(unlocked('gol_10'), isTrue);
    expect(unlocked('svizzero'), isTrue);
    expect(unlocked('fuoriclasse'), isTrue);
    expect(unlocked('anni_1'), isTrue);
    // I più rari prima: Fuoriclasse (leggenda), poi gli ori.
    expect(topBadges(list).first.id, 'fuoriclasse');
    expect(topBadges(list), hasLength(3));
  });

  test(
    'carte speciali: ognuna si festeggia una volta sola, anche quando la più '
    'recente sparisce o cambia reparto',
    () async {
      final flags = MemoryFlags();
      expect(await firstTimeSpecialCard(flags, 'p1', 'a'), isTrue);
      expect(await firstTimeSpecialCard(flags, 'p1', 'b'), isTrue);
      // La carta b sparisce: torna valida la a, già festeggiata.
      expect(await firstTimeSpecialCard(flags, 'p1', 'a'), isFalse);
      expect(await firstTimeSpecialCard(flags, 'p1', 'b'), isFalse);
      // Chi aggiorna l'app: la carta vista con la versione di prima non si rifesteggia.
      await flags.setString('special.seen.p2', 'c');
      expect(await firstTimeSpecialCard(flags, 'p2', 'c'), isFalse);
      expect(await firstTimeSpecialCard(flags, 'p2', 'd'), isTrue);
    },
  );

  testWidgets('Carta: traguardi e walkout', (tester) async {
    await startApp(tester);
    await goToSection(tester, 'Rosa completa');
    await tester.ensureVisible(find.text('MARCO ROSSI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MARCO ROSSI'));
    await tester.pumpAndSettle();

    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('48/50'), 200, scrollable: page);
    expect(
      find.textContaining(RegExp(r'^TRAGUARDI · \d+ DI 11$')),
      findsOneWidget,
    );
    expect(find.text('Presenza fissa'), findsOneWidget);
    expect(find.text('48/50'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Guarda il walkout'),
      -200,
      scrollable: page,
    );
    await tester.tap(find.text('Guarda il walkout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('ATT'), findsOneWidget); // ruolo rivelato
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('CARTA DELLA SETTIMANA'), findsOneWidget);
    expect(
      find.text(
        'Il Direttivo ha scelto Marco Rossi per l\'attacco della 2ª giornata.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    expect(find.text('CARTA GIOCATORE'), findsOneWidget);
  });
}
