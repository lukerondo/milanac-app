import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_repository.dart';
import 'package:milanac/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startAt(
    WidgetTester tester,
    String path, {
    required RulesRepository rules,
    Profile? profile,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        rulesRepositoryProvider.overrideWithValue(rules),
        if (profile != null)
          profileProvider.overrideWith(
            (ref) => Stream<Profile?>.value(profile),
          ),
      ],
    );
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(path);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Senza regolamento pubblicato il Direttivo entra, lo scrive e lo pubblica',
    (tester) async {
      final repo = DemoRulesRepository.unpublished();
      final container = await startAt(
        tester,
        '/regolamento/accetta',
        rules: repo,
      );
      expect(find.text('REGOLAMENTO NON ANCORA PUBBLICATO'), findsOneWidget);
      await tester.tap(find.text('Entra e scrivilo'));
      await tester.pumpAndSettle();

      // Editor del primo Direttivo: spiegazione, "Più tardi", niente articoli.
      expect(find.text('REGOLAMENTO D\'INGRESSO'), findsOneWidget);
      expect(find.textContaining('tocca a te'), findsOneWidget);
      expect(
        find.text('Nessun articolo: aggiungi il primo e poi pubblica.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Più tardi'));
      await tester.pumpAndSettle();
      expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
      expect(container.read(rulesWriteLaterProvider), isTrue);

      // Dalla Sala Direttivo resta il promemoria.
      container.read(routerProvider).go('/direttivo');
      await tester.pumpAndSettle();
      expect(find.text('Regolamento d\'ingresso da scrivere'), findsOneWidget);
      await tester.tap(find.text('Regolamento d\'ingresso da scrivere'));
      await tester.pumpAndSettle();
      expect(find.text('REGOLAMENTO D\'INGRESSO'), findsOneWidget);

      // Primo articolo e pubblicazione: si torna alla Home.
      await tester.tap(find.text('Nuovo articolo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Titolo'),
        'Art. 1 – Ingresso',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Testo'),
        'Benvenuto nel club: rispetto e puntualità.',
      );
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(find.text('Art. 1 – Ingresso'), findsOneWidget);
      await tester.tap(find.text('PUBBLICA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pubblica'));
      await tester.pumpAndSettle();
      expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);

      // Da ora la pagina di accettazione mostra la pergamena con l'articolo.
      container.read(routerProvider).go('/regolamento/accetta');
      await tester.pumpAndSettle();
      expect(find.text('ART. 1 – INGRESSO'), findsOneWidget);
      expect(find.text('Ho letto e accetto'), findsOneWidget);
      expect(find.text('REGOLAMENTO NON ANCORA PUBBLICATO'), findsNothing);
    },
  );

  testWidgets('Senza regolamento pubblicato un giocatore entra subito', (
    tester,
  ) async {
    await startAt(
      tester,
      '/regolamento/accetta',
      rules: DemoRulesRepository.unpublished(),
      profile: const Profile(
        id: 'nuovo',
        displayName: 'Mario',
        role: ClubRole.pending,
        requestedRole: ClubRole.giocatore,
        registrationCompleted: true,
      ),
    );
    expect(find.text('REGOLAMENTO NON ANCORA PUBBLICATO'), findsOneWidget);
    expect(find.textContaining('Entra pure'), findsOneWidget);
    await tester.tap(find.text('Entra nel club'));
    await tester.pumpAndSettle();
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
  });
}
