import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_repository.dart';
import 'package:milanac/main.dart';

/// Indietro di Android sulle pagine che si aprono da sole (notifiche, link, promemoria):
/// si torna alla pagina da cui si arriva di solito, l'app non si chiude.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startApp(
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
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> go(ProviderContainer container, WidgetTester tester, String to) {
    container.read(routerProvider).go(to);
    return tester.pumpAndSettle();
  }

  /// Il tasto indietro: true se l'app l'ha gestito (cioè non si chiude).
  Future<bool> back(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    return handled;
  }

  testWidgets(
    'Profilo aperto dalla notifica delle carte speciali: indietro porta '
    'alla Home',
    (tester) async {
      final container = await startApp(tester);
      await go(container, tester, '/carta');
      expect(find.text('IL TUO PROFILO'), findsOneWidget);
      expect(await back(tester), isTrue, reason: 'l\'app non si chiude');
      expect(find.text('IL TUO PROFILO'), findsNothing);
      expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    },
  );

  testWidgets(
    'Impostazioni aperte da sole: indietro porta al profilo, poi alla '
    'Home',
    (tester) async {
      final container = await startApp(tester);
      await go(container, tester, '/impostazioni?sezione=notifiche');
      expect(find.text('IMPOSTAZIONI'), findsOneWidget);
      expect(await back(tester), isTrue);
      expect(find.text('IL TUO PROFILO'), findsOneWidget);
      expect(await back(tester), isTrue);
      expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);

      // Aperte dal profilo invece tornano indietro come sempre.
      await tester.tap(find.byTooltip('Il tuo profilo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Impostazioni'));
      await tester.pumpAndSettle();
      expect(await back(tester), isTrue);
      expect(find.text('IL TUO PROFILO'), findsOneWidget);
      expect(await back(tester), isTrue);
      expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    },
  );

  testWidgets('Editor iniziale del regolamento: indietro vale "Più tardi"; '
      'dal promemoria della Sala Direttivo si torna lì', (tester) async {
    final container = await startApp(
      tester,
      overrides: [
        rulesRepositoryProvider.overrideWithValue(
          DemoRulesRepository.unpublished(),
        ),
      ],
    );
    // Dalla porta d'ingresso del primo Direttivo.
    await go(container, tester, '/regolamento/scrivi');
    expect(find.text('REGOLAMENTO D\'INGRESSO'), findsOneWidget);
    expect(await back(tester), isTrue, reason: 'l\'app non si chiude');
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    expect(container.read(rulesWriteLaterProvider), isTrue);

    // Dal promemoria della Sala Direttivo (aperto con go: niente sotto).
    await go(container, tester, '/direttivo');
    await tester.tap(find.text('Regolamento d\'ingresso da scrivere'));
    await tester.pumpAndSettle();
    expect(find.text('REGOLAMENTO D\'INGRESSO'), findsOneWidget);
    expect(await back(tester), isTrue);
    expect(find.text('REGOLAMENTO D\'INGRESSO'), findsNothing);
    expect(find.text('DA FARE OGGI'), findsOneWidget);

    // Anche "Più tardi" riporta alla Sala Direttivo.
    await tester.tap(find.text('Regolamento d\'ingresso da scrivere'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('DA FARE OGGI'), findsOneWidget);
  });
}
