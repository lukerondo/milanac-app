import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/formazione/formation_repository.dart';
import 'package:milanac/features/formazione/modules.dart';

import 'formazione_test.dart' show openFormationEditor;
import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;

/// La riga di un ruolo nella sezione "Palle inattive".
Finder setPieceTile(SetPiece role) =>
    find.ancestor(of: find.text(role.label), matching: find.byType(ListTile));

/// Il testo sotto il ruolo: chi batte ("9 Marco Rossi · ATT") o "Da scegliere".
String takerOf(WidgetTester tester, SetPiece role) =>
    (tester.widget<ListTile>(setPieceTile(role)).subtitle! as Text).data!;

/// Apre dall'editor il foglio per scegliere chi batte [role].
Future<void> openTakerSheet(WidgetTester tester, SetPiece role) async {
  await tester.ensureVisible(setPieceTile(role));
  await tester.pumpAndSettle();
  await tester.tap(setPieceTile(role));
  await tester.pumpAndSettle();
}

/// Sceglie chi batte [role] dall'editor ([choice] come appare nel foglio).
Future<void> pickTaker(
  WidgetTester tester,
  SetPiece role,
  String choice,
) async {
  await openTakerSheet(tester, role);
  await tester.tap(find.text(choice));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('battitori: dal database all\'app e ritorno', () {
    final row = <String, dynamic>{
      'id': 'f1',
      'module': '4-3-3',
      'published_at': '2026-11-04T18:00:00Z',
      'updated_at': '2026-11-04T18:00:00Z',
      'published_module': '4-3-3',
      'published_players': {'0': 'p4', '9': 'p2'},
      'formation_slots': [
        {'slot_index': 0, 'player_id': 'p4'},
        {'slot_index': 2, 'player_id': null},
        {'slot_index': 9, 'player_id': 'p2'},
      ],
      // "via" ha eliminato l'account (non è più tra i titolari); "barriera" è una
      // chiave che quest'app non conosce.
      'set_pieces': {
        'rigori': 'p2',
        'angoli_sx': 'p4',
        'angoli_dx': 'via',
        'barriera': 'p2',
      },
      'published_set_pieces': {'rigori': 'p2', 'punizioni': 'p3'},
    };
    final f = formationFromRow(row, Team.milanac);
    expect(f.setPieces, {SetPiece.rigori: 'p2', SetPiece.angoliSinistra: 'p4'});
    expect(f.publishedSetPieces, {
      SetPiece.rigori: 'p2',
    }, reason: 'p3 non era tra i titolari pubblicati');
    expect(f.publishedView.setPieces, {SetPiece.rigori: 'p2'});
    expect(f.setPiecesOf('p2'), [SetPiece.rigori]);
    // Come li vogliono save_formation e la pubblicazione, e indietro.
    expect(setPiecesJson(f.setPieces), {'rigori': 'p2', 'angoli_sx': 'p4'});
    expect(parseSetPieces(setPiecesJson(f.setPieces)), f.setPieces);
    expect(parseSetPieces(null), isEmpty);
    expect(parseSetPieces({'rigori': 7}), isEmpty);

    // Database senza i battitori (migrazione 0035 non applicata): nessuno.
    final old = formationFromRow(
      {...row}
        ..remove('set_pieces')
        ..remove('published_set_pieces'),
      Team.milanac,
    );
    expect(old.setPieces, isEmpty);
    expect(old.publishedSetPieces, isNull);
    expect(old.publishedView.setPieces, isEmpty);
    expect(old.hasUnpublishedChanges, isFalse);
  });

  test('un battitore è sempre un titolare: chi esce dal campo perde i suoi '
      'ruoli, chi si sposta li tiene', () {
    const f = Formation(
      players: {0: 'p4', 2: 'p3', 9: 'p2'},
      setPieces: {
        SetPiece.rigori: 'p2',
        SetPiece.angoliDestra: 'p2',
        SetPiece.punizioni: 'p4',
      },
    );
    // Rossi passa da ATT a TS: resta in campo, tiene rigori e angoli.
    expect(f.assign(1, 'p2').setPieces, f.setPieces);
    // Rossi libera il posto: i suoi ruoli restano da scegliere.
    expect(f.assign(9, null).setPieces, {SetPiece.punizioni: 'p4'});
    // Al suo posto entra un altro: lo stesso.
    expect(f.assign(9, 'p6').setPieces, {SetPiece.punizioni: 'p4'});
    // Si sceglie solo tra i titolari; null toglie il ruolo.
    expect(f.withSetPiece(SetPiece.angoliSinistra, 'p3').setPieces, {
      ...f.setPieces,
      SetPiece.angoliSinistra: 'p3',
    });
    expect(
      f.withSetPiece(SetPiece.angoliSinistra, 'p6').setPieces,
      f.setPieces,
      reason: 'p6 è in panchina',
    );
    expect(f.withSetPiece(SetPiece.rigori, null).setPieces, {
      SetPiece.angoliDestra: 'p2',
      SetPiece.punizioni: 'p4',
    });
  });

  test('"modificata dopo la pubblicazione" guarda anche i battitori', () {
    final published = Formation(
      players: const {9: 'p2'},
      setPieces: const {SetPiece.rigori: 'p2'},
      publishedAt: DateTime.utc(2026, 11, 4, 18),
      publishedModule: defaultModule,
      publishedPlayers: const {9: 'p2'},
      publishedSetPieces: const {SetPiece.rigori: 'p2'},
    );
    expect(published.hasUnpublishedChanges, isFalse);
    expect(
      published.withSetPiece(SetPiece.punizioni, 'p2').hasUnpublishedChanges,
      isTrue,
    );
    expect(
      published.withSetPiece(SetPiece.rigori, null).hasUnpublishedChanges,
      isTrue,
    );
    // Pubblicata prima dei battitori: lo è finché non se ne sceglie uno.
    final before = Formation(
      players: const {9: 'p2'},
      publishedAt: DateTime.utc(2026, 11, 4, 18),
      publishedModule: defaultModule,
      publishedPlayers: const {9: 'p2'},
    );
    expect(before.hasUnpublishedChanges, isFalse);
    expect(
      before.withSetPiece(SetPiece.rigori, 'p2').hasUnpublishedChanges,
      isTrue,
    );
  });

  test('la riga dei battitori in Comunicazioni (come set_pieces_line del '
      'database)', () {
    const names = {'p2': 'Rossi', 'p3': 'Bianchi', 'p6': 'Verdi', 'p4': 'Neri'};
    String? line(Map<SetPiece, String> takers) =>
        setPiecesLine(takers, (id) => names[id]);
    expect(
      line({
        SetPiece.rigori: 'p2',
        SetPiece.punizioni: 'p3',
        SetPiece.angoliSinistra: 'p6',
        SetPiece.angoliDestra: 'p4',
      }),
      'Palle inattive: rigori Rossi · punizioni Bianchi · angoli sx Verdi, '
      'dx Neri',
    );
    expect(
      line({
        SetPiece.rigori: 'p2',
        SetPiece.punizioni: 'p2',
        SetPiece.angoliSinistra: 'p6',
        SetPiece.angoliDestra: 'p6',
      }),
      'Palle inattive: rigori Rossi · punizioni Rossi · angoli Verdi',
    );
    expect(
      line({SetPiece.angoliDestra: 'p4'}),
      'Palle inattive: angoli dx Neri',
    );
    expect(
      line({SetPiece.angoliSinistra: 'p6', SetPiece.punizioni: 'p3'}),
      'Palle inattive: punizioni Bianchi · angoli sx Verdi',
    );
    // Chi non è più nel club non si scrive; senza battitori nessuna riga.
    expect(
      line({SetPiece.rigori: 'via', SetPiece.angoliDestra: 'p4'}),
      'Palle inattive: angoli dx Neri',
    );
    expect(line({SetPiece.rigori: 'via'}), isNull);
    expect(line(const {}), isNull);
  });

  test(
    'i battitori dell\'ultima formazione pubblicata, per la lavagna',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = publishedSetPiecesProvider(Team.milanac);
      container.listen(provider, (_, _) {});
      expect(
        await container.read(provider.future),
        isEmpty,
        reason: 'non ancora pubblicata',
      );
      final repository = container.read(formationRepositoryProvider);
      await repository.publish(await repository.loadCurrent(Team.milanac));
      container.invalidate(formationProvider);
      expect(await container.read(provider.future), {
        SetPiece.rigori: 'p2',
        SetPiece.punizioni: 'demo',
        SetPiece.angoliSinistra: 'demo',
        SetPiece.angoliDestra: 'p2',
      });
      // La bozza cambia, i battitori pubblicati no.
      final draft = await repository.loadCurrent(Team.milanac);
      await repository.save(draft.withSetPiece(SetPiece.rigori, 'p3'));
      container.invalidate(formationProvider);
      expect((await container.read(provider.future))[SetPiece.rigori], 'p2');
    },
  );

  testWidgets('Palle inattive: il Direttivo sceglie chi batte tra i titolari, '
      'toglie un ruolo, e chi esce dal campo perde i suoi', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    await openFormationEditor(tester);
    expect(find.text('PALLE INATTIVE'), findsOneWidget);
    // In demo: rigori e angoli da destra a Rossi, punizioni e angoli da sinistra al Demo.
    expect(takerOf(tester, SetPiece.rigori), '9 Marco Rossi · ATT');
    expect(takerOf(tester, SetPiece.punizioni), '10 Demo Direttivo · CDC');
    expect(takerOf(tester, SetPiece.angoliSinistra), '10 Demo Direttivo · CDC');
    expect(takerOf(tester, SetPiece.angoliDestra), '9 Marco Rossi · ATT');

    // Le punizioni a Bianchi: nel foglio solo i titolari, dal portiere all'attacco.
    await openTakerSheet(tester, SetPiece.punizioni);
    expect(find.text('CHI BATTE LE PUNIZIONI?'), findsOneWidget);
    expect(find.text('Nessun battitore'), findsOneWidget);
    final starters = [
      '1 Andrea Neri',
      '4 Luca Bianchi',
      '10 Demo Direttivo',
      '9 Marco Rossi',
    ];
    expect(
      [for (final t in starters) tester.getTopLeft(find.text(t)).dy],
      orderedEquals(
        [for (final t in starters) tester.getTopLeft(find.text(t)).dy]..sort(),
      ),
    );
    expect(find.textContaining('batte già: punizioni'), findsOneWidget);
    await tester.tap(find.text('4 Luca Bianchi'));
    await tester.pumpAndSettle();
    expect(takerOf(tester, SetPiece.punizioni), '4 Luca Bianchi · DC');

    // Gli angoli da sinistra restano da scegliere.
    await pickTaker(tester, SetPiece.angoliSinistra, 'Nessun battitore');
    expect(takerOf(tester, SetPiece.angoliSinistra), 'Da scegliere');

    // Rossi esce dal campo: rigori e angoli da destra tornano da scegliere.
    await tester.ensureVisible(find.text('9 Rossi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 Rossi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libera la posizione'));
    await tester.pumpAndSettle();
    expect(takerOf(tester, SetPiece.rigori), 'Da scegliere');
    expect(takerOf(tester, SetPiece.angoliDestra), 'Da scegliere');
    // ...e non si può più scegliere.
    await openTakerSheet(tester, SetPiece.rigori);
    expect(find.text('CHI BATTE I RIGORI?'), findsOneWidget);
    expect(find.text('9 Marco Rossi'), findsNothing);
    expect(find.text('Nessun battitore'), findsNothing);
    Navigator.of(tester.element(find.text('CHI BATTE I RIGORI?'))).pop();
    await tester.pumpAndSettle();
    // Salvato così: solo le punizioni a Bianchi.
    final repository = container.read(formationRepositoryProvider);
    expect((await repository.loadCurrent(Team.milanac)).setPieces, {
      SetPiece.punizioni: 'p3',
    });

    // Pubblicata: i giocatori vedono solo i ruoli assegnati.
    await tester.tap(find.text('Pubblica la formazione di stasera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Pubblica'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await goToSection(tester, 'Formazione');
    expect(find.text('Pubblicata oggi'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PALLE INATTIVE'), 200);
    expect(takerOf(tester, SetPiece.punizioni), '4 Luca Bianchi · DC');
    expect(find.text('Rigori'), findsNothing);
    expect(find.text('Da scegliere'), findsNothing);
    expect(
      await container.read(publishedSetPiecesProvider(Team.milanac).future),
      {SetPiece.punizioni: 'p3'},
    );
  });

  for (final appearance in [Appearance.chiaro, Appearance.scuro]) {
    testWidgets('Chi batte già si vede nel foglio, anche nel tema '
        '${appearance.label.toLowerCase()}: fondo oro, nome in oro e spunta', (
      tester,
    ) async {
      final container = await startAppAt(tester, todayInItalyAt(17));
      await container.read(appearanceProvider.notifier).set(appearance);
      await openFormationEditor(tester);
      final p = appearance == Appearance.chiaro
          ? AppPalette.light
          : AppPalette.dark;
      // In demo i rigori sono di Rossi.
      await openTakerSheet(tester, SetPiece.rigori);
      Finder row(String name) =>
          find.ancestor(of: find.text(name), matching: find.byType(ListTile));
      Color? nameColor(String name) => tester
          .renderObject<RenderParagraph>(find.text(name))
          .text
          .style
          ?.color;
      Color? background(String name) {
        final ink = tester.widget<Ink>(
          find.descendant(of: row(name), matching: find.byType(Ink)),
        );
        return (ink.decoration! as ShapeDecoration).color;
      }

      expect(tester.widget<ListTile>(row('9 Marco Rossi')).selected, isTrue);
      expect(nameColor('9 Marco Rossi'), p.accentText);
      expect(background('9 Marco Rossi'), p.accentTint);
      expect(
        find.descendant(
          of: row('9 Marco Rossi'),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
      // Gli altri come sempre: nome nel colore del testo, senza fondo né spunta.
      expect(tester.widget<ListTile>(row('4 Luca Bianchi')).selected, isFalse);
      expect(nameColor('4 Luca Bianchi'), p.text);
      expect(nameColor('9 Marco Rossi'), isNot(nameColor('4 Luca Bianchi')));
      expect(background('4 Luca Bianchi'), isNot(p.accentTint));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      Navigator.of(tester.element(find.text('CHI BATTE I RIGORI?'))).pop();
      await tester.pumpAndSettle();

      // Lo stesso nel foglio "Chi gioca": Rossi è già lì, non "verrà spostato".
      await tester.ensureVisible(find.text('9 Rossi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9 Rossi'));
      await tester.pumpAndSettle();
      expect(find.text('CHI GIOCA ATT?'), findsOneWidget);
      expect(tester.widget<ListTile>(row('Marco Rossi')).selected, isTrue);
      expect(nameColor('Marco Rossi'), p.accentText);
      expect(background('Marco Rossi'), p.accentTint);
      expect(
        find.descendant(
          of: row('Marco Rossi'),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
      expect(
        (tester.widget<ListTile>(row('Marco Rossi')).subtitle! as Text).data,
        'ATT',
      );
      expect(nameColor('Luca Bianchi'), p.text);
    });
  }

  testWidgets('Palle inattive: la sezione nascosta ai giocatori se nessuno '
      'batte', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    final repository = container.read(formationRepositoryProvider);
    final draft = await repository.loadCurrent(Team.milanac);
    await repository.publish(draft.copyWith(setPieces: const {}));
    await goToSection(tester, 'Formazione');
    expect(find.text('Pubblicata oggi'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PANCHINA'), 200);
    expect(find.text('PALLE INATTIVE'), findsNothing);
  });

  for (final width in [320.0, 360.0]) {
    for (final appearance in [Appearance.scuro, Appearance.chiaro]) {
      testWidgets(
        'Palle inattive su un telefono largo ${width.toInt()} dp, tema '
        '${appearance.label.toLowerCase()}: niente sborda',
        (tester) async {
          final container = await startAppAt(tester, todayInItalyAt(17));
          await container.read(appearanceProvider.notifier).set(appearance);
          tester.view.physicalSize = Size(width * 3, 640 * 3);
          await tester.pumpAndSettle();
          // Nomi lunghi: il Futuro con Verdi, che batte quasi tutto.
          await goToSection(tester, 'Sala Direttivo');
          await scrollAndTap(tester, find.text('Formazioni da pubblicare'));
          await tester.tap(find.text('FUTURO'));
          await tester.pumpAndSettle();
          for (final role in SetPiece.values) {
            await tester.scrollUntilVisible(
              setPieceTile(role),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(
              takerOf(tester, role),
              role == SetPiece.angoliDestra
                  ? 'Da scegliere'
                  : '23 Paolo Verdi · CC',
            );
          }
          await pickTaker(tester, SetPiece.angoliDestra, '1 Andrea Neri');
          expect(takerOf(tester, SetPiece.angoliDestra), '1 Andrea Neri · POR');
          await openTakerSheet(tester, SetPiece.angoliSinistra);
          expect(
            find.text('CHI BATTE GLI ANGOLI DA SINISTRA?'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          Navigator.of(
            tester.element(find.text('CHI BATTE GLI ANGOLI DA SINISTRA?')),
          ).pop();
          await tester.pumpAndSettle();

          // Pubblicata, come la vedono i giocatori.
          await scrollAndTap(
            tester,
            find.text('Pubblica la formazione di stasera'),
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Pubblica'));
          await tester.pumpAndSettle();
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pumpAndSettle();
          await goToPath(tester, '/formazione?squadra=futuro');
          await tester.scrollUntilVisible(
            setPieceTile(SetPiece.angoliDestra),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            takerOf(tester, SetPiece.angoliSinistra),
            '23 Paolo Verdi · CC',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
