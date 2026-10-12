import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/formazione/formation_repository.dart';
import 'package:milanac/features/formazione/formazione_page.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/ui.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;
import 'presenze_test.dart' show testAccountProvider;

/// Formazioni su un server lento: ogni salvataggio resta "in corso" mezzo secondo.
class _SlowFormations implements FormationRepository {
  final saved = <Team, Formation>{};

  /// Le formazioni ricevute dai salvataggi, nell'ordine.
  final received = <Formation>[];
  Formation? published;
  var fail = false;

  @override
  Future<Formation> loadCurrent(Team team) async =>
      saved[team] ?? Formation(team: team);

  @override
  Future<Formation> save(Formation f) async {
    received.add(f);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (fail) throw Exception('server irraggiungibile');
    return saved[f.team] = f.copyWith(
      id: f.id.isEmpty ? 'nuova-${received.length}' : f.id,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Formation> publish(Formation f) async {
    return published = saved[f.team] = f.copyWith(
      publishedAt: DateTime.now().toUtc(),
      publishedModule: f.module,
      publishedPlayers: Map.of(f.players),
    );
  }
}

class _CountingFormations extends DemoFormationRepository {
  var reads = 0;

  @override
  Future<Formation> loadCurrent(Team team) {
    reads++;
    return super.loadCurrent(team);
  }
}

/// Dalla Sala Direttivo all'editor delle formazioni (su uno schermo alto).
Future<void> openFormationEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4800);
  await tester.pumpAndSettle();
  await goToSection(tester, 'Sala Direttivo');
  await tester.tap(find.text('Formazioni da pubblicare'));
  await tester.pumpAndSettle();
}

FilledButton publishButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );

FilterPill moduleChip(WidgetTester tester, String module) =>
    tester.widget<FilterPill>(find.widgetWithText(FilterPill, module));

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('i posti come li vuole save_formation', () {
    final json = formationSlotsJson(
      const Formation(module: '4-4-2', players: {0: 'p4', 9: 'p2'}),
    );
    expect(json, hasLength(11));
    expect(json.first, {
      'slot_index': 0,
      'x': .5,
      'y': .92,
      'label': 'POR',
      'player_id': 'p4',
    });
    expect(json[9]['label'], 'ATT');
    expect(json[9]['player_id'], 'p2');
    expect(json[1]['player_id'], isNull, reason: 'posto libero');
  });

  test('"modificata dopo la pubblicazione" guarda modulo e giocatori, non '
      'gli orari', () {
    final published = Formation(
      module: '4-4-2',
      players: const {0: 'p4', 9: 'p2'},
      publishedAt: DateTime.utc(2026, 10, 12, 18),
      // Salvata poco dopo con l'ora del server, più avanti di quella del telefono.
      updatedAt: DateTime.utc(2026, 10, 12, 18, 5),
      publishedModule: '4-4-2',
      publishedPlayers: const {0: 'p4', 9: 'p2'},
    );
    expect(published.hasUnpublishedChanges, isFalse);
    expect(published.copyWith(module: '3-5-2').hasUnpublishedChanges, isTrue);
    expect(published.assign(9, 'p3').hasUnpublishedChanges, isTrue);
    expect(published.assign(9, null).hasUnpublishedChanges, isTrue);
    expect(const Formation().hasUnpublishedChanges, isFalse);
    // Pubblicata oggi in Italia: le 23:30 UTC del 12 sono già il 13.
    final lateNight = published.copyWith(
      publishedAt: DateTime.utc(2026, 10, 12, 23, 30),
    );
    expect(lateNight.isPublishedOn(DateTime(2026, 10, 13)), isTrue);
    expect(lateNight.isPublishedOn(DateTime(2026, 10, 12)), isFalse);
  });

  test('ogni modulo ha 11 posizioni, portiere per primo, dentro il campo', () {
    for (final entry in formationModules.entries) {
      expect(entry.value, hasLength(11), reason: entry.key);
      expect(entry.value.first.label, 'POR', reason: entry.key);
      for (final s in entry.value) {
        expect(s.x, inInclusiveRange(0, 1));
        expect(s.y, inInclusiveRange(0, 1));
      }
    }
  });

  test('assegnare un giocatore già in campo lo sposta', () {
    const f = Formation(players: {1: 'a', 2: 'b'});
    final next = f.assign(5, 'a');
    expect(next.players, {2: 'b', 5: 'a'});
    expect(next.assign(2, null).players, {5: 'a'});
  });

  testWidgets('Formazione: il Direttivo schiera un giocatore e cambia modulo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, 'Formazione');

    // I giocatori vedono solo la formazione pubblicata: per ora non c'è.
    expect(
      find.textContaining('non è ancora stata pubblicata'),
      findsOneWidget,
    );
    await tester.tap(find.text('Prepara la formazione'));
    await tester.pumpAndSettle();
    expect(find.text('FORMAZIONI'), findsOneWidget);

    // In demo: Neri (POR), Bianchi, Demo, Rossi in campo. Nessuno in panchina.
    expect(find.text('1 Neri'), findsOneWidget);
    const summary =
        "4 giocatori in campo, 7 ruoli all'IA. Chi è in panchina resta a "
        'disposizione per tutta la serata.';
    await tester.scrollUntilVisible(find.text(summary), 200);
    expect(find.text(summary), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tutti i giocatori sono in campo.'),
      200,
    );
    expect(find.text('Tutti i giocatori sono in campo.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 Neri'), -200);

    // Libera il portiere: Neri finisce in panchina e il suo posto passa all'IA.
    await tester.tap(find.text('1 Neri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libera la posizione'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Andrea Neri'),
      findsOneWidget,
    ); // chip in panchina

    // Cambio modulo: i giocatori restano schierati.
    await tester.scrollUntilVisible(find.text('3-5-2'), -200);
    await tester.tap(find.text('3-5-2'));
    await tester.pumpAndSettle();
    expect(find.text('9 Rossi'), findsOneWidget);

    // Pubblicazione: conferma, poi lo stato diventa "Pubblicata oggi".
    await tester.scrollUntilVisible(find.textContaining('Bozza'), -200);
    expect(find.textContaining('Bozza'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pubblica la formazione di stasera'),
      200,
    );
    await tester.ensureVisible(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pubblica'));
    await tester.pumpAndSettle();
    expect(find.text('Ripubblica e avvisa i giocatori'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Pubblicata oggi'),
      -200,
    );
    expect(find.textContaining('Pubblicata oggi'), findsOneWidget);

    // Tornando alla sezione Formazione: la versione pubblicata (3-5-2, Neri in panchina).
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.textContaining('non è ancora stata pubblicata'), findsNothing);
    expect(find.text('Pubblicata oggi'), findsOneWidget);
    expect(find.text('3-5-2'), findsOneWidget);
    expect(find.text('9 Rossi'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Andrea Neri'), 200);
    expect(find.textContaining('Andrea Neri'), findsOneWidget);
  });

  testWidgets('Sala Direttivo: una formazione per squadra', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, 'Sala Direttivo');
    await tester.scrollUntilVisible(
      find.text('Formazioni da pubblicare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formazioni da pubblicare'));
    await tester.pumpAndSettle();

    expect(find.text('9 Rossi'), findsOneWidget);
    await tester.tap(find.text('Futuro'));
    await tester.pumpAndSettle();
    // Formazione del Futuro: Neri in porta e Verdi; Rossi non c'è.
    expect(find.text('23 Verdi'), findsOneWidget);
    expect(find.text('1 Neri'), findsOneWidget);
    expect(find.text('9 Rossi'), findsNothing);
  });

  testWidgets('Formazione: "Prepara la formazione" apre l\'editor sulla squadra '
      'che si sta guardando', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    await goToSection(tester, 'Formazione');
    await tester.tap(find.text('Futuro'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('La formazione di Milan AC Futuro non è ancora'),
      findsOneWidget,
    );
    await tester.tap(find.text('Prepara la formazione'));
    await tester.pumpAndSettle();
    expect(find.text('FORMAZIONI'), findsOneWidget);
    // Nell'editor il Futuro (Verdi), non il Milan AC (Rossi).
    expect(find.text('23 Verdi'), findsOneWidget);
    expect(find.text('9 Rossi'), findsNothing);
    expect(container.read(formationTeamProvider), Team.futuro);
  });

  testWidgets('pulsante del PDF nella barra in alto: acceso solo con la '
      'formazione pubblicata della squadra mostrata', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    // Come lo mette il router nella barra della sezione Formazione.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            appBar: AppBar(actions: const [FormationPdfAction()]),
            body: const FormazionePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    IconButton pdf() => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.download_rounded),
    );
    expect(find.byTooltip('Scarica il PDF della formazione'), findsOneWidget);
    expect(pdf().onPressed, isNull, reason: 'non ancora pubblicata');

    // Il Direttivo la pubblica: il pulsante si accende.
    final server = container.read(formationRepositoryProvider);
    await server.publish(await server.loadCurrent(Team.milanac));
    container.invalidate(formationProvider);
    await tester.pumpAndSettle();
    expect(pdf().onPressed, isNotNull);

    // Il Futuro non è pubblicato: di nuovo spento.
    await tester.tap(find.text('Futuro'));
    await tester.pumpAndSettle();
    expect(pdf().onPressed, isNull);
  });

  testWidgets('Formazione: salvataggi uno alla volta e "Pubblica" solo a '
      'salvataggio finito, con i dati salvati', (tester) async {
    final formations = _SlowFormations();
    await startAppAt(
      tester,
      todayInItalyAt(17),
      overrides: [formationRepositoryProvider.overrideWithValue(formations)],
    );
    await openFormationEditor(tester);
    // Futuro: la formazione non esiste ancora.
    await tester.tap(find.text('Futuro'));
    await tester.pumpAndSettle();

    // Due cambi di modulo di fila: il secondo mentre il primo si sta salvando.
    await tester.tap(find.text('3-5-2'));
    await tester.pump();
    await tester.tap(find.text('4-4-2'));
    await tester.pump();
    expect(moduleChip(tester, '4-4-2').selected, isTrue);
    expect(publishButton(tester, 'Salvataggio in corso…').onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Nell'ordine; il secondo usa l'id appena creato (niente seconda formazione).
    expect(
      [for (final f in formations.received) (f.id, f.module)],
      [('', '3-5-2'), ('nuova-1', '4-4-2')],
    );
    expect(formations.saved[Team.futuro]!.module, '4-4-2');

    expect(
      publishButton(tester, 'Pubblica la formazione di stasera').onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pubblica'));
    await tester.pumpAndSettle();
    expect(formations.published!.id, 'nuova-1');
    expect(formations.published!.module, '4-4-2');
    expect(find.text('Ripubblica e avvisa i giocatori'), findsOneWidget);
  });

  testWidgets('Formazione: se il salvataggio non riesce si torna all\'ultima '
      'salvata', (tester) async {
    final formations = _SlowFormations()..fail = true;
    await startAppAt(
      tester,
      todayInItalyAt(17),
      overrides: [formationRepositoryProvider.overrideWithValue(formations)],
    );
    await openFormationEditor(tester);

    await tester.tap(find.text('3-5-2'));
    await tester.pump();
    expect(moduleChip(tester, '3-5-2').selected, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Salvataggio non riuscito. Riprova.'), findsOneWidget);
    expect(moduleChip(tester, '4-3-3').selected, isTrue);
    expect(
      publishButton(tester, 'Pubblica la formazione di stasera').onPressed,
      isNotNull,
    );
  });

  test('la formazione si rilegge quando entra un altro account', () async {
    final formations = _CountingFormations();
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(testAccountProvider),
        ),
        formationRepositoryProvider.overrideWithValue(formations),
      ],
    );
    addTearDown(container.dispose);
    final milanac = formationProvider(Team.milanac);
    container.listen(milanac, (_, _) {});
    expect((await container.read(milanac.future)).id, 'demo');
    container.read(testAccountProvider.notifier).enter('b');
    expect((await container.read(milanac.future)).id, 'demo');
    expect(formations.reads, 2);
    container.read(testAccountProvider.notifier).enter(null);
    expect((await container.read(milanac.future)).id, isEmpty);
    expect(formations.reads, 2);
  });

  testWidgets('Formazione: chi la guarda vede la pubblicazione fatta da un '
      'altro telefono, senza riavviare l\'app', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    await goToSection(tester, 'Formazione');
    expect(
      find.textContaining('non è ancora stata pubblicata'),
      findsOneWidget,
    );
    // Il Direttivo pubblica da un altro telefono (qui: direttamente sul "server").
    final server = container.read(formationRepositoryProvider);
    Future<void> publishElsewhere(String module) async => server.publish(
      (await server.loadCurrent(Team.milanac)).copyWith(module: module),
    );

    // Riaprendo la sezione (dalla notifica) si rilegge.
    await publishElsewhere('4-3-3');
    await goToSection(tester, 'Home');
    await goToSection(tester, 'Formazione');
    expect(find.textContaining('non è ancora stata pubblicata'), findsNothing);
    expect(find.text('4-3-3'), findsOneWidget);

    // Tornando in primo piano.
    await publishElsewhere('3-5-2');
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('3-5-2'), findsOneWidget);

    // Con la pagina aperta (la notifica arriva in primo piano): entro un minuto.
    await publishElsewhere('4-4-2');
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('4-4-2'), findsOneWidget);

    // E trascinando in giù il campo.
    await publishElsewhere('5-3-2');
    await tester.fling(
      find.textContaining('giocatori in campo'),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('5-3-2'), findsOneWidget);
  });
}
