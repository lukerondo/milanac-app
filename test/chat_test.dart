import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Chat: canali, non letti, invio e silenzia', (tester) async {
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
    expect(find.text('Stasera tutti in lobby alle 21:15!'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Forza MILANAC!');
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
  });
}
