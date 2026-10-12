import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    Size screen = const Size(360, 780),
  }) async {
    tester.view.physicalSize = screen * 3;
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

      // Da ora la pagina di accettazione mostra il regolamento con l'articolo.
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

  /// Club con un regolamento di un solo articolo, già pubblicato (versione 1).
  Future<DemoRulesRepository> shortRules({bool slow = false}) async {
    final repo = slow ? _SlowRules() : DemoRulesRepository.unpublished();
    await repo.saveArticle(
      const RulesArticle(
        sortOrder: 0,
        title: 'Art. 1 – Ingresso',
        body: 'Rispetto e puntualità.',
      ),
    );
    await repo.publish();
    return repo;
  }

  ButtonStyleButton acceptButton(WidgetTester tester) => tester.widget(
    find.ancestor(
      of: find.text('Ho letto e accetto'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );

  // Tablet in verticale: il regolamento corto sta tutto nello schermo.
  const tablet = Size(800, 1280);

  testWidgets('Regolamento corto: si accetta senza dover scorrere', (
    tester,
  ) async {
    // Rete lenta: la pagina parte con la rotella, poi arriva il testo.
    await startAt(
      tester,
      '/regolamento/accetta',
      rules: await shortRules(slow: true),
      screen: tablet,
    );
    expect(find.text('ART. 1 – INGRESSO'), findsOneWidget);
    expect(find.text('Scorri fino in fondo per poter accettare'), findsNothing);
    expect(acceptButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'Regolamento comparso dopo un ricaricamento: il pulsante si abilita lo stesso',
    (tester) async {
      final repo = DemoRulesRepository.unpublished();
      await startAt(
        tester,
        '/regolamento/accetta',
        rules: repo,
        screen: tablet,
      );
      expect(find.text('REGOLAMENTO NON ANCORA PUBBLICATO'), findsOneWidget);

      // Nel frattempo un altro del Direttivo lo pubblica: l'ingresso senza regolamento
      // viene rifiutato e la pagina mostra quello appena uscito.
      await repo.saveArticle(
        const RulesArticle(
          sortOrder: 0,
          title: 'Art. 1 – Ingresso',
          body: 'Rispetto e puntualità.',
        ),
      );
      await repo.publish();
      await tester.tap(find.text('Entra e scrivilo'));
      await tester.pumpAndSettle();
      expect(find.text('C\'è un regolamento da accettare'), findsOneWidget);
      expect(find.text('ART. 1 – INGRESSO'), findsOneWidget);
      expect(acceptButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'Nuova versione uscita mentre si legge: si carica e si accetta quella',
    (tester) async {
      final repo = await shortRules();
      await startAt(
        tester,
        '/regolamento/accetta',
        rules: repo,
        screen: tablet,
      );
      expect(find.textContaining('Versione 1'), findsOneWidget);

      // Il Direttivo pubblica la versione 2 mentre il membro legge la 1.
      await repo.saveArticle(
        const RulesArticle(
          sortOrder: 1,
          title: 'Art. 2 – Novità',
          body: 'Le amichevoli si giocano il martedì.',
        ),
      );
      await repo.publish();
      await tester.pump(const Duration(minutes: 2));
      await tester.tap(find.text('Ho letto e accetto'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'È uscita una nuova versione del regolamento: leggila e accetta.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Versione 2'), findsOneWidget);
      expect(find.text('ART. 2 – NOVITÀ'), findsOneWidget);
      // L'avviso copre il pulsante finché non sparisce.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // La nuova versione si legge da capo: di nuovo il tempo minimo.
      await tester.tap(find.text('Ho letto e accetto'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Servono 2 minuti di lettura'),
        findsOneWidget,
      );
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ho letto e accetto'));
      await tester.pumpAndSettle();
      expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
    },
  );

  testWidgets('Il tempo di lettura non scorre con l\'app in background', (
    tester,
  ) async {
    Future<void> lifecycle(AppLifecycleState state) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.lifecycle.name,
          SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
          (_) {},
        );

    await startAt(
      tester,
      '/regolamento/accetta',
      rules: await shortRules(),
      screen: tablet,
    );
    await lifecycle(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 5));
    await lifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho letto e accetto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Servono 2 minuti di lettura'), findsOneWidget);

    // In primo piano invece conta.
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho letto e accetto'));
    await tester.pumpAndSettle();
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
  });
}

/// Il regolamento arriva con qualche secondo di ritardo (rete lenta).
class _SlowRules extends DemoRulesRepository {
  _SlowRules() : super.unpublished();

  @override
  Future<RulesVersion?> latest() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    return super.latest();
  }
}
