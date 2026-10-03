import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/voti/ratings_repository.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<ProviderContainer> startApp(WidgetTester tester) async {
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
  return container;
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('settimana da lunedì', () {
    expect(weekStart(DateTime(2026, 10, 3, 22)), DateTime(2026, 9, 28));
    expect(weekStart(DateTime(2026, 9, 28)), DateTime(2026, 9, 28));
  });

  test('demo: Uomo partita con almeno 2 voti', () async {
    final repo = DemoRatingsRepository();
    final summary = await repo.summary('m1');
    expect(summary.first.playerId, 'p2');
    expect(summary.first.average, 8.5);
    expect(summary.first.isMvp, isTrue);
    await repo.saveRatings('m1', {'p3': 10});
    expect(await repo.myRatings('m1'), {'p3': 10});
    expect(
      (await repo.summary('m1')).firstWhere((s) => s.playerId == 'p3').average,
      7.7,
    );
  });

  testWidgets('Partita: Uomo partita e voto ai compagni', (tester) async {
    await startApp(tester);
    await goToSection(tester, 'Risultati partite');
    await tester.tap(find.text('Dinamo Pixel'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('VOTI E UOMO PARTITA'), 200);
    expect(find.text('Marco Rossi'), findsWidgets);
    expect(find.text('8.5'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Vota i compagni'), -200);
    await tester.tap(find.text('Vota i compagni'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('lascia a "–" chi non ha giocato'),
      findsOneWidget,
    );

    // Voto 10 al primo compagno (cursore tutto a destra).
    final slider = find.byType(Slider).first;
    final box = tester.getRect(slider);
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsWidgets);
    await tester.tap(find.text('Salva i voti'));
    await tester.pumpAndSettle();
    expect(find.text('Voti salvati (1). Grazie!'), findsOneWidget);
    expect(find.text('Modifica i tuoi voti (1)'), findsOneWidget);
  });

  testWidgets('Squadra della settimana con le carte speciali', (tester) async {
    await startApp(tester);
    await goToSection(tester, 'Squadra della settimana');
    expect(find.text('SQUADRA DELLA SETTIMANA'), findsWidgets);
    expect(find.text('ATTACCO'), findsOneWidget);
    expect(find.text('ROSSI'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ULTIMI UOMINI PARTITA'), 200);
    expect(find.text('Marco Rossi'), findsOneWidget);
  });
}
