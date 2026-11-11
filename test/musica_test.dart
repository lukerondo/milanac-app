import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Colonna sonora: le canzoni del club, il file dal telefono, il '
      'muto e la musica tolta', (tester) async {
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

    // Nella demo (lettore muto) la musica parte tolta: niente muto in alto.
    expect(find.byTooltip('Metti in muto'), findsNothing);
    await goToSection(tester, 'Colonna sonora');
    expect(find.text('COLONNA SONORA'), findsOneWidget);
    expect(find.text('Nessuna musica'), findsOneWidget);

    // La colonna sonora del club, con il muto sempre in alto.
    await tester.tap(find.text('Ascolta la colonna sonora del club'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Metti in muto'), findsOneWidget);
    expect(find.text('Canzoni autoprodotte'), findsOneWidget);
    expect(
      find.text('La colonna sonora del club · suonata da noi'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Stemma MILANAC'), findsOneWidget);
    expect(find.byTooltip('Metti in pausa'), findsOneWidget);

    // Un file dal telefono al suo posto, poi di nuovo il club.
    await tester.tap(find.text('Scegli un file dal telefono'));
    await tester.pumpAndSettle();
    expect(find.text('Canzoni iconiche FIFA.mp3'), findsOneWidget);
    expect(find.text('Scelto dal tuo telefono'), findsOneWidget);
    await tester.tap(find.text('Torna alla colonna sonora del club'));
    await tester.pumpAndSettle();
    expect(find.text('Canzoni autoprodotte'), findsOneWidget);
    expect(find.text('Torna alla colonna sonora del club'), findsNothing);

    // Muto dalla barra in alto.
    await tester.tap(find.byTooltip('Metti in muto'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fai partire la musica'), findsOneWidget);
    expect(find.byTooltip('Riattiva la musica'), findsOneWidget);

    // Il pulsante grande la fa ripartire; in muto il lettore resta fermo.
    await tester.tap(find.byTooltip('Fai partire la musica'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Metti in muto'), findsOneWidget);
    await tester.tap(find.byTooltip('Metti in pausa'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Riattiva la musica'), findsOneWidget);

    // Musica tolta: niente muto in alto.
    await tester.tap(find.text('Togli la musica'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna musica'), findsOneWidget);
    expect(find.text('Ascolta la colonna sonora del club'), findsOneWidget);
    expect(find.byTooltip('Riattiva la musica'), findsNothing);
    expect(find.byTooltip('Metti in muto'), findsNothing);

    // Sotto, le playlist e i video del club.
    await tester.scrollUntilVisible(
      find.text('Le canzoni più iconiche di FIFA'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Le canzoni più iconiche di FIFA'), findsOneWidget);
  });
}
