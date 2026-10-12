import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/tornei/tournaments_repository.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('classifica: punti, differenza reti, gol fatti', () {
    final rows = sortStandings(const [
      StandingRow(
        teamName: 'B',
        won: 1,
        drawn: 1,
        goalsFor: 3,
        goalsAgainst: 1,
      ),
      StandingRow(
        teamName: 'A',
        won: 1,
        drawn: 1,
        goalsFor: 5,
        goalsAgainst: 3,
      ),
      StandingRow(teamName: 'C', won: 2, lost: 3),
    ]);
    expect(rows.map((r) => r.teamName), ['C', 'A', 'B']);
    expect(rows.first.points, 6);
    expect(rows.first.played, 5);
  });

  testWidgets('Tornei: elenco con stato e classifica, dettaglio', (
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
    await goToSection(tester, 'Tornei');

    // Il torneo in corso con la classifica e il sito, poi quello con le iscrizioni.
    expect(find.text('FVPA SERIE B'), findsOneWidget);
    expect(find.text('Milan AC · in corso dal 15 settembre'), findsOneWidget);
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Squadra'), findsOneWidget);
    expect(find.text('Dinamo Pixel'), findsOneWidget);
    expect(find.text('Sito del torneo'), findsOneWidget);
    expect(find.text('COPPA RISERVE'), findsOneWidget);
    expect(find.text('Milan AC Futuro · Torneo amatoriale'), findsOneWidget);
    expect(find.text('Iscrizioni'), findsOneWidget);

    await tester.tap(find.text('FVPA SERIE B'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'TORNEO'), findsOneWidget);
    expect(find.text('CLASSIFICA'), findsOneWidget);
    expect(find.text('Dinamo Pixel'), findsWidgets);
    await tester.scrollUntilVisible(find.text('PARTITE'), 200);
    expect(find.text('PARTITE'), findsOneWidget);
  });

  testWidgets(
    'Classifica aggiornata da un altro telefono: si vede al ritorno in '
    'primo piano, aprendo il torneo e trascinando in giù',
    (tester) async {
      final container = await startAppAt(tester, todayInItalyAt(17));
      await goToSection(tester, 'Tornei');
      expect(find.text('Dinamo Pixel'), findsOneWidget);
      final server = container.read(tournamentsRepositoryProvider);

      // Non arriva in tempo reale: al ritorno in primo piano.
      await server.saveStandings('tr1', const [
        StandingRow(teamName: 'Atletico Virtuale', won: 3),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Atletico Virtuale'), findsNothing);
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
      expect(find.text('Atletico Virtuale'), findsOneWidget);
      expect(find.text('Dinamo Pixel'), findsNothing);

      // Aprendo il torneo.
      await server.saveStandings('tr1', const [
        StandingRow(teamName: 'Real Joystick', won: 4),
      ]);
      await tester.tap(find.text('FVPA SERIE B'));
      await tester.pumpAndSettle();
      expect(find.text('Real Joystick'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Real Joystick'), findsOneWidget);

      // Trascinando in giù l'elenco dei tornei.
      await server.saveStandings('tr1', const [
        StandingRow(teamName: 'Sporting Joypad', won: 5),
      ]);
      await tester.fling(find.text('FVPA SERIE B'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Sporting Joypad'), findsOneWidget);
    },
  );

  testWidgets('Torneo: data di fine, date che si tolgono e limiti della '
      'tabella', (tester) async {
    final container = await startAppAt(tester, todayInItalyAt(17));
    await goToSection(tester, 'Tornei');
    await tester.tap(find.text('FVPA SERIE B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifica torneo'));
    await tester.pumpAndSettle();

    // Il nome non supera gli 80 caratteri della tabella.
    final name = find.widgetWithText(TextField, 'Nome del torneo');
    await tester.enterText(name, 'x' * 100);
    expect(tester.widget<TextField>(name).controller!.text, hasLength(80));
    await tester.enterText(name, 'FVPA Serie B');

    // La data d'inizio si toglie, quella di fine si sceglie.
    expect(find.text('Inizio: 15 settembre 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Togli la data (inizio)'));
    await tester.pumpAndSettle();
    expect(find.text('Data di inizio (facoltativa)'), findsOneWidget);
    await tester.tap(find.text('Data di fine (facoltativa)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fine: 20 '), findsOneWidget);

    await tester.ensureVisible(find.text('Salva torneo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva torneo'));
    await tester.pumpAndSettle();
    final saved = container
        .read(tournamentsProvider)
        .value!
        .firstWhere((t) => t.id == 'tr1');
    expect(saved.startsOn, isNull);
    expect(saved.endsOn?.day, 20);
  });

  testWidgets(
    'Nuovo torneo: se la foto non parte, "Salva" di nuovo non crea un '
    'doppione; la foto sostituita sparisce',
    (tester) async {
      final repo = _FlakyPhotos();
      final container = await startAppAt(
        tester,
        todayInItalyAt(17),
        overrides: [tournamentsRepositoryProvider.overrideWithValue(repo)],
      );
      // La galleria del telefono: restituisce un'immagine vera.
      final dir = Directory.systemTemp.createTempSync('milanac_tornei');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}/logo.png')..writeAsBytesSync(_png);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => photo.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        ),
      );
      Future<void> pickPhoto(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        // Il file si legge davvero dal disco: fuori dal tempo finto dei test.
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
      }

      Future<void> save() async {
        await tester.ensureVisible(find.text('Salva torneo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salva torneo'));
        await tester.pumpAndSettle();
      }

      List<Tournament> named(String name) => [
        for (final t in container.read(tournamentsProvider).value!)
          if (t.name == name) t,
      ];

      await goToSection(tester, 'Tornei');
      await tester.tap(find.text('Nuovo torneo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nome del torneo'),
        'Coppa Lombardia',
      );
      await pickPhoto('Foto o logo del torneo');
      repo.failUploads = 1;
      await save();
      expect(find.textContaining('Nessuna connessione'), findsOneWidget);
      expect(named('Coppa Lombardia'), hasLength(1));
      // Il messaggio sparisce da solo.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Di nuovo: lo stesso torneo, con la foto.
      await save();
      expect(
        find.text('Nuovo torneo'),
        findsOneWidget,
        reason: 'foglio chiuso',
      );
      final created = named('Coppa Lombardia');
      expect(created, hasLength(1));
      final first = created.single.imagePath!;
      expect(demoTournamentPhotos, contains(first));

      // Foto cambiata: la vecchia si toglie, a torneo aggiornato.
      await tester.tap(find.text('COPPA LOMBARDIA'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Modifica torneo'));
      await tester.pumpAndSettle();
      await pickPhoto('Cambia foto o logo');
      await save();
      final second = named('Coppa Lombardia').single.imagePath!;
      expect(second, isNot(first));
      expect(demoTournamentPhotos, contains(second));
      expect(demoTournamentPhotos, isNot(contains(first)));
      demoTournamentPhotos.remove(second);
    },
  );
}

/// Tornei della demo con il caricamento della foto che non riesce per [failUploads]
/// volte (rete caduta dopo aver creato il torneo).
class _FlakyPhotos extends DemoTournamentsRepository {
  var failUploads = 0;

  @override
  Future<String> uploadImage(
    String tournamentId,
    Uint8List bytes, {
    String? replacing,
  }) async {
    if (failUploads > 0) {
      failUploads--;
      throw const SocketException('rete assente');
    }
    return super.uploadImage(tournamentId, bytes, replacing: replacing);
  }
}

/// Un'immagine PNG di 1×1 pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
