import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/auth_repository.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> pumpLogin(WidgetTester tester) async {
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
    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Accesso: social, email e password dimenticata', (tester) async {
    await pumpLogin(tester);
    expect(find.text('MILANO SIAMO NOI!'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Accedi'), findsOneWidget);
    expect(find.text('Password dimenticata?'), findsOneWidget);

    // Email mancante: avviso, nessun invio.
    await tester.tap(find.text('Password dimenticata?'));
    await tester.pump();
    expect(find.text('Scrivi un indirizzo email valido.'), findsOneWidget);
    // Lascia sparire l'avviso prima del prossimo (entra, resta 4 s, esce).
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'mario@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'corta');
    await tester.tap(find.text('Accedi'));
    await tester.pump();
    expect(
      find.text('La password deve avere almeno 8 caratteri.'),
      findsOneWidget,
    );
  });

  testWidgets('Registrazione con email: attesa della conferma', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('Non hai un account? Registrati'));
    await tester.pumpAndSettle();
    expect(find.text('Crea il mio account'), findsOneWidget);
    expect(find.text('Password dimenticata?'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'nuovo@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password (almeno 8 caratteri)'),
      'milanac-2026',
    );
    await tester.tap(find.text('Crea il mio account'));
    await tester.pumpAndSettle();
    expect(find.text('Controlla la tua email'), findsOneWidget);
    expect(find.textContaining('nuovo@example.com'), findsOneWidget);

    await tester.tap(find.text('Usa un\'altra email'));
    await tester.pumpAndSettle();
    expect(find.text('Crea il mio account'), findsOneWidget);
  });

  test('errori di accesso in italiano', () {
    expect(
      friendlyAuthError(Exception('Invalid login credentials')),
      'Email o password non corretti.',
    );
    expect(
      friendlyAuthError(Exception('Email not confirmed')),
      contains('Conferma prima la tua email'),
    );
    expect(
      friendlyAuthError(Exception('User already registered')),
      contains('Esiste già un account'),
    );
  });
}
