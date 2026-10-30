import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/errors.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/lavagna/board_model.dart';
import 'package:milanac/features/tattiche/tactics_repository.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<void> openTattiche(
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
  await goToSection(tester, 'Tattiche & Build');
}

/// Il repository demo che si ricorda l'ultimo schema ricevuto.
class _SpyTactics extends DemoTacticsRepository {
  Tactic? saved;

  @override
  Future<void> save(
    Tactic tactic, {
    Uint8List? image,
    String imageContentType = 'image/jpeg',
  }) {
    saved = tactic;
    return super.save(tactic, image: image, imageContentType: imageContentType);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Tattiche: le build dei creator portano a Mondo Proclub', (
    tester,
  ) async {
    await openTattiche(tester);
    await scrollAndTap(tester, find.text('Build per ruolo'));
    expect(find.text('MONDO PROCLUB'), findsOneWidget);
    // Indietro si torna alle Tattiche.
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('TATTICHE'), findsOneWidget);
  });

  testWidgets('Tattiche: il Direttivo pubblica uno schema', (tester) async {
    await openTattiche(tester);
    expect(find.text('Pressing alto dopo palla persa'), findsOneWidget);

    await tester.tap(find.text('Nuova tattica'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Ripartenza veloce',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Spiegazione'),
      'Il portiere apre sul DC destro.',
    );
    await tester.ensureVisible(find.text('Salva tattica'));
    await tester.tap(find.text('Salva tattica'));
    await tester.pumpAndSettle();
    expect(find.text('Ripartenza veloce'), findsOneWidget);

    await tester.tap(find.text('Ripartenza veloce'));
    await tester.pumpAndSettle();
    expect(find.text('TATTICA'), findsOneWidget);
    expect(find.text('Il portiere apre sul DC destro.'), findsOneWidget);
  });

  testWidgets(
    'Tattiche: cambiare il testo di uno schema non ne cancella il disegno',
    (tester) async {
      final spy = _SpyTactics();
      await openTattiche(
        tester,
        overrides: [tacticsRepositoryProvider.overrideWithValue(spy)],
      );
      // Lo schema con la lavagna, più in basso nell'elenco.
      await scrollAndTap(tester, find.text('Uscita dal basso'));
      expect(find.text('Apri la lavagna'), findsOneWidget);

      await tester.tap(find.byTooltip('Modifica'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Spiegazione'),
        'Il portiere apre sul DC sinistro.',
      );
      await tester.ensureVisible(find.text('Salva tattica'));
      await tester.tap(find.text('Salva tattica'));
      await tester.pumpAndSettle();

      // Al salvataggio arrivano anche lavagna e squadra (prima: null, e il database
      // le cancellava).
      expect(spy.saved!.board!.tokens, hasLength(12));
      expect(spy.saved!.team, 'milanac');
      // Lo schema resta disegnato, con il testo nuovo.
      expect(find.text('Il portiere apre sul DC sinistro.'), findsOneWidget);
      expect(find.text('Apri la lavagna'), findsOneWidget);
      final t3 = (await spy.watchAll().first).firstWhere((t) => t.id == 't3');
      expect(t3.board!.arrows, hasLength(2));
      expect(t3.description, 'Il portiere apre sul DC sinistro.');
    },
  );

  test(
    'schema: i campi vuoti non si scrivono (né cancellano quelli salvati)',
    () async {
      // Verso il database: lavagna e squadra solo se ci sono.
      final soloTesto = const Tactic(id: 't3', title: 'Solo testo').toMap();
      expect(soloTesto.containsKey('board'), isFalse);
      expect(soloTesto.containsKey('team'), isFalse);
      final conLavagna = Tactic(
        id: 't3',
        title: 'Con lavagna',
        board: demoBoard(),
        team: 'milanac',
      ).toMap();
      expect((conLavagna['board'] as Map)['tokens'], hasLength(12));
      expect(conLavagna['team'], 'milanac');

      // La demo si comporta come il database.
      final repo = DemoTacticsRepository();
      await repo.save(const Tactic(id: 't3', title: 'Uscita dal basso (2)'));
      final t3 = (await repo.watchAll().first).firstWhere((t) => t.id == 't3');
      expect(t3.title, 'Uscita dal basso (2)');
      expect(t3.board, isNotNull);
      expect(t3.team, 'milanac');
      // Uno schema eliminato nel frattempo non si "salva" in silenzio.
      await expectLater(
        repo.save(const Tactic(id: 'eliminato', title: 'x')),
        throwsA(isA<AppError>()),
      );
    },
  );
}
