import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/clock.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/musica/soundtrack.dart';
import 'package:milanac/features/rosa/rosa_page.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';
import 'home_test.dart' show todayAt;
import 'rosa_view.dart';

/// Risultati, partita, tornei, rosa, carte speciali, Mondo Proclub, albo d'oro,
/// colonna sonora e profilo con l'aspetto "Chiaro": ogni pagina usa la tavolozza
/// chiara e si apre senza errori né testo che sborda.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startLight(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final now = todayAt(17);
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(() => now)],
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
    // "Chiaro" scelto in Impostazioni → Aspetto.
    await container.read(appearanceProvider.notifier).set(Appearance.chiaro);
    await tester.pumpAndSettle();
    return container;
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
  Future<void> scrollToEnd(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Tema chiaro: risultati, partita e tornei', (tester) async {
    await startLight(tester);

    await goToSection(tester, 'Risultati');
    expectLight(tester, find.text('ULTIMI RISULTATI'));
    expectLight(tester, find.text('Dinamo Pixel'));

    await tester.tap(find.text('Dinamo Pixel'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('MARCATORI'));
    expectLight(tester, find.text('CARTE SPECIALI DELLA GIORNATA'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('Highlights completi'));
    expectLight(tester, find.text('Modifica carte della giornata'));
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();

    await goToSection(tester, 'Tornei');
    expectLight(tester, find.text('FVPA SERIE B'));
    expectLight(tester, find.text('Sito del torneo'));
    await tester.tap(find.text('FVPA SERIE B'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('CLASSIFICA'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('PARTITE'));
  });

  testWidgets('Tema chiaro: rosa, carte speciali, profilo e carta di un '
      'compagno', (tester) async {
    await startLight(tester);

    await goToSection(tester, 'Rosa completa');
    expectLight(tester, find.text('MARCO ROSSI'));
    await showRosaAs(tester, RosaView.elenco);
    expectLight(tester, find.text('DIRETTIVO'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('Paolo Verdi'));
    await showRosaAs(tester, RosaView.carte);

    await goToSection(tester, 'Carte speciali');
    expectLight(tester, find.text('NERO/ORO DELLA SETTIMANA'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('STORICO'));
    await tester.tap(find.text('1ª giornata · Sporting Joypad 0 – 1'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('STORICO'));

    await goToSection(tester, 'La mia carta');
    expectLight(tester, find.text('Rivedi il walkout'));
    expectLight(tester, find.text('Gamertag'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('STATISTICHE'));
    expectLight(tester, find.textContaining('TRAGUARDI ·'));

    // La carta di un compagno, dalla Rosa.
    await goToPath(tester, '/rosa');
    await tester.tap(find.text('ANDREA NERI'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('CARTA GIOCATORE'));
    expectLight(tester, find.text('Guarda il walkout'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('Condividi la carta'));
  });

  testWidgets('Tema chiaro: Mondo Proclub, albo d\'oro e colonna sonora', (
    tester,
  ) async {
    final c = await startLight(tester);

    await goToSection(tester, 'Mondo Proclub');
    expectLight(tester, find.text('VIDEO DEI CREATOR'));
    await tester.tap(find.text('Notizie'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('DA FARE PRIMA DELLA PARTITA'));
    expectLight(tester, find.text('NOTIZIE'));
    await scrollToEnd(tester);
    expectLight(tester, find.textContaining('Ultimate Team'));

    await goToSection(tester, "Albo d'oro");
    expectLight(tester, find.textContaining('Bacheca ancora vuota'));
    await tester.tap(find.text('2025/26'));
    await tester.pumpAndSettle();
    expectLight(tester, find.text('TROFEI'));
    expectLight(tester, find.text('Aggiungi un trofeo'));

    await goToSection(tester, 'Colonna sonora');
    expectLight(tester, find.text('Nessuna musica scelta'));
    await c.read(soundtrackProvider.notifier).pickTrack();
    await tester.pumpAndSettle();
    expectLight(tester, find.text('Scelto dal tuo telefono'));
    await scrollToEnd(tester);
    expectLight(tester, find.text('PLAYLIST E VIDEO'));
    // In muto, così il lettore non resta acceso a fine prova.
    await c.read(soundtrackProvider.notifier).toggleMute();
    await tester.pumpAndSettle();
  });
}
