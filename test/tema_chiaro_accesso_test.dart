import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/auth/gate_ui.dart';
import 'package:milanac/features/auth/pending_page.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_reader.dart';
import 'package:milanac/features/regolamento/rules_repository.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

/// Accesso, registrazione, regolamento e impostazioni con l'aspetto "Chiaro": ogni
/// pagina usa la tavolozza chiara e si apre senza errori né testo che sborda.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startLight(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    // "Chiaro" scelto in una volta precedente: l'app parte già in chiaro.
    await container.read(localFlagsProvider).setString('aspetto', 'chiaro');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String path) async {
    c.read(routerProvider).go(path);
    await tester.pumpAndSettle();
  }

  /// La pagina con [anchor] usa la tavolozza chiara e finora non ci sono errori.
  void expectLight(WidgetTester tester, Finder anchor) {
    expect(anchor, findsWidgets);
    final context = tester.element(anchor.first);
    expect(Theme.of(context).brightness, Brightness.light);
    expect(context.pal.brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  }

  /// Scorre fino in fondo la prima lista della pagina.
  Future<void> scrollToEnd(WidgetTester tester, Finder scrollable) async {
    for (var i = 0; i < 12; i++) {
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Tema chiaro: accesso, registrazione, nuova password, attesa', (
    tester,
  ) async {
    final c = await startLight(tester);

    await go(tester, c, '/login');
    expectLight(tester, find.text('Password dimenticata?'));
    expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    await tester.ensureVisible(find.text('Registrati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrati'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('CREA IL TUO ACCOUNT'));

    await go(tester, c, '/registrazione?passo=1');
    expectLight(tester, find.text('Passo 1 di 3'));
    await scrollToEnd(tester, find.byType(Scrollable).first);
    expectLight(tester, find.text('Avanti'));

    await go(tester, c, '/nuova-password');
    expectLight(tester, find.text('Annulla'));

    await go(tester, c, '/registrazione?passo=2');
    expectLight(tester, find.text('Passo 2 di 3'));
    await tester.tap(find.text('Direttivo'));
    await tester.pumpAndSettle();
    await scrollToEnd(tester, find.byType(Scrollable).first);
    expectLight(tester, find.text('Passo 2 di 3'));

    await go(tester, c, '/login');
    await go(tester, c, '/registrazione?passo=3');
    expectLight(tester, find.text('Passo 3 di 3'));
    await tester.tap(find.text('A caso'));
    await tester.pumpAndSettle();
    await scrollToEnd(tester, find.byType(Scrollable).first);
    expectLight(tester, find.byType(ChoicePill));
    expectLight(tester, find.text('Completa la registrazione'));

    // Account sospeso: in demo la pagina di blocco rimanda alla Home, la si apre da sola.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const PendingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectLight(tester, find.text('Esci'));
  });

  testWidgets('Tema chiaro: accettazione del regolamento', (tester) async {
    final c = await startLight(tester);
    await go(tester, c, '/regolamento/accetta');
    expectLight(tester, find.text('Ho letto e accetto'));
    await scrollToEnd(
      tester,
      find
          .descendant(
            of: find.byType(RulesReader),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expectLight(tester, find.text('Ho letto e accetto'));

    // Troppo presto: l'avviso dei 2 minuti, anche lui con i colori chiari.
    await tester.tap(find.text('Ho letto e accetto'));
    await tester.pumpAndSettle();
    expectLight(tester, find.textContaining('Servono 2 minuti di lettura'));
  });

  testWidgets('Tema chiaro: regolamento non ancora pubblicato', (tester) async {
    final c = await startLight(
      tester,
      overrides: [
        rulesRepositoryProvider.overrideWithValue(
          DemoRulesRepository.unpublished(),
        ),
        profileProvider.overrideWith(
          (ref) => Stream<Profile?>.value(
            const Profile(
              id: 'nuovo',
              displayName: 'Mario',
              role: ClubRole.pending,
              requestedRole: ClubRole.giocatore,
              registrationCompleted: true,
            ),
          ),
        ),
      ],
    );
    await go(tester, c, '/regolamento/accetta');
    expectLight(tester, find.text('REGOLAMENTO NON ANCORA PUBBLICATO'));
    expectLight(tester, find.text('Entra nel club'));
  });

  testWidgets(
    'Tema chiaro: regolamento e storia, impostazioni, volto e privacy',
    (tester) async {
      await startLight(tester);

      await goToSection(tester, 'Regolamento & Storia');
      expectLight(tester, find.text('ORGANIGRAMMA'));
      await tester.tap(find.byTooltip('Modifica il regolamento'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('BOZZA DEL REGOLAMENTO'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Storia'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('LA NOSTRA STORIA'));
      await tester.tap(find.byTooltip('Modifica la storia'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('MODIFICA LA STORIA'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await goToSection(tester, 'Impostazioni');
      expectLight(tester, find.text('IMPOSTAZIONI'));

      await tester.tap(find.text('Dati personali'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('DATI PERSONALI'));
      await scrollToEnd(tester, find.byType(Scrollable).first);
      expectLight(tester, find.text('Salva i dati'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Editor del volto: anteprima, "A caso" e tutte le righe di scelta.
      await tester.tap(find.text('Il tuo volto'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('IL TUO VOLTO'));
      await tester.tap(find.text('A caso'));
      await tester.pumpAndSettle();
      await scrollToEnd(tester, find.byType(Scrollable).first);
      expectLight(tester, find.byType(ChoicePill));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('Volto aggiornato'), findsNothing);

      await tester.ensureVisible(find.text('Cambia password'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cambia password'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('Ripeti la nuova password'));
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Privacy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expectLight(tester, find.text('Informativa sulla privacy'));
      await scrollToEnd(tester, find.byType(Scrollable).first);
      expectLight(tester, find.text('PRIVACY'));
    },
  );
}
