import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

Future<void> openTattiche(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  await goToSection(tester, 'Tattiche & Build');
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Build: filtro per ruolo e nuovo video', (tester) async {
    await openTattiche(tester);
    expect(find.text('La build da attaccante più forte'), findsOneWidget);

    await tester.tap(find.text('Aggiungi build'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Build DC impassabile',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'youtu.be/abc123',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DC').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Build DC impassabile'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'ATT'));
    await tester.pumpAndSettle();
    expect(find.text('Build DC impassabile'), findsNothing);
    expect(find.text('La build da attaccante più forte'), findsOneWidget);
  });

  testWidgets('Tattiche: il Direttivo pubblica uno schema', (tester) async {
    await openTattiche(tester);
    await tester.tap(find.text('Tattiche'));
    await tester.pumpAndSettle();
    expect(find.text('Pressing alto dopo palla persa'), findsOneWidget);

    await tester.tap(find.text('Nuova tattica'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Titolo'),
      'Uscita dal basso',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Spiegazione'),
      'Il portiere apre sul DC destro.',
    );
    await tester.ensureVisible(find.text('Salva tattica'));
    await tester.tap(find.text('Salva tattica'));
    await tester.pumpAndSettle();
    expect(find.text('Uscita dal basso'), findsOneWidget);

    await tester.tap(find.text('Uscita dal basso'));
    await tester.pumpAndSettle();
    expect(find.text('TATTICA'), findsOneWidget);
    expect(find.text('Il portiere apre sul DC destro.'), findsOneWidget);
  });
}
