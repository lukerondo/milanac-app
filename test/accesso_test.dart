import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/auth_repository.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/auth/offline_page.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  test('registrazione con un\'email già iscritta: nessuna email, si propone l\'accesso', () {
    User user(List<UserIdentity> identities) => User(
      id: 'u1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
      identities: identities,
    );
    const identity = UserIdentity(
      id: 'u1',
      userId: 'u1',
      identityData: {},
      identityId: 'i1',
      provider: 'email',
      createdAt: '2026-10-01T00:00:00Z',
      lastSignInAt: '2026-10-01T00:00:00Z',
    );
    expect(
      signUpResultOf(AuthResponse(user: user(const []))),
      EmailSignUpResult.alreadyRegistered,
    );
    expect(
      signUpResultOf(AuthResponse(user: user(const [identity]))),
      EmailSignUpResult.needsConfirmation,
    );
  });

  test('link dell\'email scaduti o già usati: si avvisa, la rete no', () {
    const expired =
        'Il link dell\'email non è più valido (scaduto o già usato): '
        'chiedine uno nuovo.';
    // Link scaduto: Supabase rimanda all'app con error_code=otp_expired.
    expect(
      authLinkErrorText(
        const AuthException(
          'Email link is invalid or has expired',
          statusCode: 'otp_expired',
          code: 'access_denied',
        ),
      ),
      expired,
    );
    // Link già usato (codice PKCE già scambiato).
    expect(
      authLinkErrorText(
        const AuthApiException(
          'invalid flow state, no valid flow state found',
          statusCode: '404',
          code: 'flow_state_not_found',
        ),
      ),
      expired,
    );
    // Rinnovo della sessione senza rete, sessione persa all'avvio: niente avvisi.
    expect(authLinkErrorText(AuthRetryableFetchException()), isNull);
    expect(
      authLinkErrorText(
        const AuthException('Session expired.', code: 'session_expired'),
      ),
      isNull,
    );
    expect(authLinkErrorText(Exception('altro')), isNull);
  });

  testWidgets('Nessuna connessione: Riprova rilegge il profilo', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) {
            loads++;
            return Stream<Profile?>.error(
              Exception('SocketException: Failed host lookup'),
            );
          }),
        ],
        child: MaterialApp(theme: buildTheme(), home: const OfflinePage()),
      ),
    );
    await tester.pump();
    expect(
      find.text('Nessuna connessione: controlla la rete e riprova.'),
      findsOneWidget,
    );
    final before = loads;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    expect(loads, before + 1);
  });
}
