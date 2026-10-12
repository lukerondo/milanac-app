import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Colonna sonora: scelta del file e pulsante muto', (
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

    // Senza musica scelta non c'è il muto in alto; la sezione sta nel Club.
    expect(find.byTooltip('Metti in muto'), findsNothing);
    await goToSection(tester, 'Colonna sonora');
    expect(find.text('COLONNA SONORA'), findsOneWidget);
    expect(find.text('Nessuna musica scelta'), findsOneWidget);

    await tester.tap(find.text('Scegli il file audio'));
    await tester.pumpAndSettle();
    expect(find.text('Canzoni iconiche FIFA.mp3'), findsOneWidget);
    expect(find.text('Scelto dal tuo telefono'), findsOneWidget);
    expect(find.byTooltip('Metti in pausa'), findsOneWidget);

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

    // Sotto, le playlist e i video del club.
    await tester.scrollUntilVisible(
      find.text('Le canzoni più iconiche di FIFA'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Le canzoni più iconiche di FIFA'), findsOneWidget);
  });
}
