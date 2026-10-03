import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

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

    // Senza musica scelta, la nota in alto porta alla sezione.
    await tester.tap(find.byTooltip('Colonna sonora'));
    await tester.pumpAndSettle();
    expect(find.text('COLONNA SONORA'), findsOneWidget);
    expect(find.text('Le canzoni più iconiche di FIFA'), findsOneWidget);

    await tester.tap(find.text('Scegli il file audio'));
    await tester.pumpAndSettle();
    expect(find.text('Canzoni iconiche FIFA.mp3'), findsOneWidget);
    expect(find.text('In riproduzione (in loop)'), findsOneWidget);

    // Muto dalla barra in alto.
    await tester.tap(find.byTooltip('Metti in muto'));
    await tester.pumpAndSettle();
    expect(find.text('In muto'), findsOneWidget);
    expect(find.byTooltip('Riattiva la musica'), findsOneWidget);
  });
}
