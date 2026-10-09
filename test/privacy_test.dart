import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('senza parametri Firebase le notifiche sono disattivate', () {
    expect(FirebaseConfig.current, isNull);
  });

  testWidgets('Privacy raggiungibile dalle Impostazioni', (tester) async {
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
    // La Privacy sta nelle Impostazioni (ingranaggio in alto a destra).
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Privacy'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Informativa sulla privacy'), findsOneWidget);
    expect(find.textContaining('{{EMAIL}}'), findsNothing);
  });
}
