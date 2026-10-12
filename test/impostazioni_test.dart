import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/auth_repository.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/impostazioni/impostazioni_page.dart';
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

    await goToSection(tester, 'Impostazioni');
    expect(find.text('IMPOSTAZIONI'), findsOneWidget);
    expect(find.text('DATI PERSONALI'), findsOneWidget);

    // Il volto si cambia in una pagina dedicata.
    await tester.tap(find.text('Cambia il volto'));
    await tester.pumpAndSettle();
    expect(find.text('IL TUO VOLTO'), findsOneWidget);
    await tester.tap(find.text('A caso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SALVA'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Volto aggiornato'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextField, 'Città'));
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

  testWidgets('Esci: si aspetta l\'uscita sulla pagina, poi niente più ref', (
    tester,
  ) async {
    final auth = _SlowSignOut();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: LogoutTile()),
                ),
              ),
              child: const Text('Impostazioni'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    // La pagina resta aperta con l'attesa sul pulsante; un secondo tocco non conta.
    await tester.tap(find.text('Esci'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Esci'));
    await tester.pump(const Duration(seconds: 1));
    expect(auth.calls, 1);
    expect(find.byType(LogoutTile), findsOneWidget);

    // Sessione chiusa: il router porta via la pagina mentre il server risponde ancora.
    Navigator.of(tester.element(find.byType(LogoutTile))).pop();
    await tester.pumpAndSettle();
    auth.done.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Impostazioni'), findsOneWidget);
  });
}

/// Uscita lenta (rete): finisce quando lo decide il test.
class _SlowSignOut extends DemoAuthRepository {
  final done = Completer<void>();
  int calls = 0;

  @override
  Future<void> signOut() {
    calls++;
    return done.future;
  }
}
