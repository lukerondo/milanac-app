import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

/// Telefono 1080x2340 con la barra a 3 tasti in basso (48 dp), come i Samsung.
Future<void> openWithNavBar(WidgetTester tester, String section) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: navBar * 3);
  tester.view.viewPadding = const FakeViewPadding(
    top: 24 * 3,
    bottom: navBar * 3,
  );
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  await goToSection(tester, section);
}

const navBar = 48.0;
const screenHeight = 2340 / 3;

void expectAboveNavBar(WidgetTester tester, Finder finder) {
  final bottom = tester.getRect(finder).bottom;
  expect(
    bottom,
    lessThanOrEqualTo(screenHeight - navBar),
    reason: 'finisce sotto i tasti di sistema',
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Il pannello "Nuovo evento" resta sopra i tasti di sistema', (
    tester,
  ) async {
    await openWithNavBar(tester, 'Calendario partite');
    await tester.tap(find.text('Nuovo evento'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Salva evento');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expectAboveNavBar(tester, save);
  });

  testWidgets('Il bottone della Home resta sopra i tasti di sistema', (
    tester,
  ) async {
    await openWithNavBar(tester, 'Notizie');
    expectAboveNavBar(tester, find.byType(FloatingActionButton));
    // Il fondo della pagina non scorre sotto la barra.
    expectAboveNavBar(tester, find.byType(Scrollable).first);
  });
}
