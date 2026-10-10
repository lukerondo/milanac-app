import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/link_text.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('link nel testo: si riconoscono http e www, la punteggiatura resta fuori', () {
    final pieces = splitLinks(
      'Guarda https://youtu.be/abc, poi www.milanac.it. Wiki: https://it.wikipedia.org/wiki/Milan_(calcio)',
    );
    expect(pieces.map((p) => p.text).toList(), [
      'Guarda ',
      'https://youtu.be/abc',
      ', poi ',
      'www.milanac.it',
      '. Wiki: ',
      'https://it.wikipedia.org/wiki/Milan_(calcio)',
    ]);
    expect(pieces.where((p) => p.isLink).length, 3);
    expect(pieces[3].uri.toString(), 'https://www.milanac.it');
    expect(splitLinks('Nessun link qui').single.isLink, isFalse);
  });

  testWidgets('Chat stile Telegram: nuovi messaggi, risposta, vocale, allegato '
      'scaduto, elimina, silenzia', (tester) async {
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
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    // Badge dei non letti nel menu (2 in Generale + 1 in Milan AC).
    expect(
      find.descendant(of: find.byType(Drawer), matching: find.text('3')),
      findsOneWidget,
    );
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.text('Generale'), findsOneWidget);
    expect(find.text('Comunicazioni'), findsOneWidget);
    expect(find.text('Luca Bianchi: Ci sono 💪'), findsOneWidget);

    // Milan AC: la chat della squadra.
    await tester.tap(find.text('Milan AC'));
    await tester.pumpAndSettle();
    expect(find.text('Stasera provo la build nuova da DC'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.text('Stasera tutti in lobby alle 21:15!'), findsNWidgets(2));
    // Il separatore sopra il primo messaggio arrivato dopo l'ultima lettura.
    expect(find.text('Nuovi messaggi'), findsOneWidget);
    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Ieri'), findsOneWidget);
    // La foto di ieri è scaduta; il vocale di 12 secondi si può ascoltare.
    expect(find.text('Allegato scaduto'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    await tester.tap(find.byTooltip('Ascolta'));
    await tester.pumpAndSettle();
    expect(find.text('Vocale non disponibile nella demo.'), findsOneWidget);
    // L'avviso in basso sparisce dopo qualche secondo (copre la barra di scrittura).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // "Ci sono 💪" cita il messaggio di Marco Rossi.
    expect(find.text('Marco Rossi'), findsWidgets);

    // Rispondi con pressione lunga.
    await tester.longPress(find.text('Ci sono 💪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rispondi'));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Luca Bianchi'), findsOneWidget);
    // Senza testo c'è il microfono (tieni premuto); con il testo compare "Invia".
    expect(find.byTooltip('Invia'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Registra un vocale'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tieni premuto per registrare'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Grande!');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Grande!'), findsOneWidget);
    expect(find.text('Ci sono 💪'), findsNWidgets(2));
    expect(find.text('Rispondi a Luca Bianchi'), findsNothing);

    // Elimina (con conferma) il proprio messaggio.
    await tester.longPress(find.text('Grande!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina messaggio'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare il messaggio?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('Grande!'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Forza MILANAC!');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Forza MILANAC!'), findsOneWidget);

    await tester.tap(find.byTooltip('Silenzia canale'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Riattiva notifiche'), findsOneWidget);

    // Tornando alla lista: tutto letto, canale silenziato.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Demo Direttivo: Forza MILANAC!'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_rounded), findsOneWidget);

    // Tattiche: il link nel messaggio è cliccabile.
    await tester.tap(find.text('Tattiche & Schemi'));
    await tester.pumpAndSettle();
    expect(find.byType(LinkText), findsWidgets);
    expect(
      find.textContaining('https://youtu.be/dQw4w9WgXcQ', findRichText: true),
      findsOneWidget,
    );
  });
}
