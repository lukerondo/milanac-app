import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/member_photo.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('bandiera dal codice ISO', () {
    expect(flagEmoji('IT'), '🇮🇹');
    expect(flagEmoji('es'), '🇪🇸');
  });

  testWidgets('Impostazioni: dati anagrafici, poi la bandiera sulla carta', (
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

    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('IMPOSTAZIONI'), findsOneWidget);
    expect(find.text('DATI ANAGRAFICI'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Città'), 'Milano');
    await tester.ensureVisible(find.text('Nazionalità'));
    await tester.tap(find.text('Non indicata'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🇮🇹  Italia').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sinistro'));
    await tester.tap(find.text('Sinistro'));
    await tester.ensureVisible(find.text('Salva i dati'));
    await tester.tap(find.text('Salva i dati'));
    await tester.pumpAndSettle();
    expect(find.text('Dati salvati.'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await goToSection(tester, 'La mia carta');
    expect(find.text('🇮🇹'), findsOneWidget);
  });
}
