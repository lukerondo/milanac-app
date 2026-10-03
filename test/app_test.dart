import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('demo: intro, poi Notizie e menu laterale', (tester) async {
    // Schermo di uno smartphone (1080x2340).
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MilanacApp()));
    await tester.pump();
    expect(find.textContaining('Caricamento'), findsOneWidget);

    // Salta l'intro con un tocco.
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    expect(find.text('NOTIZIE'), findsOneWidget);
    expect(find.text('Leggi la notizia'), findsWidgets);

    // Apre il menu e va alla Rosa.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Chat'), findsOneWidget);
    await tester.tap(find.text('Rosa completa'));
    await tester.pumpAndSettle();
    expect(find.text('ROSA COMPLETA'), findsOneWidget);
  });

  test('intro state parte da false', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(introDoneProvider), isFalse);
    c.read(introDoneProvider.notifier).complete();
    expect(c.read(introDoneProvider), isTrue);
  });
}
