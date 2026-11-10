import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/auth_repository.dart';
import 'package:milanac/core/auth/signup_gate.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/registrazione/registration_page.dart';
import 'package:milanac/features/registrazione/registration_repository.dart';
import 'package:milanac/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers.dart';
import 'labeled_field.dart';

/// Password del club di prova (quella vera non sta mai nel codice: la imposta il
/// Direttivo dall'app e sul server resta solo cifrata).
const _club = 'club-di-prova-2026';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startAt(
    WidgetTester tester,
    DemoSignupGateRepository gate, {
    String? path,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [signupGateRepositoryProvider.overrideWithValue(gate)],
    );
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (path != null) {
      container.read(routerProvider).go(path);
      await tester.pumpAndSettle();
    }
    return container;
  }

  Future<void> openSignUp(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Registrati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrati'));
    await tester.pumpAndSettle();
  }

  /// Lascia sparire l'avviso in basso prima del prossimo.
  Future<void> clearToast(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Creare un account: serve la password del club, quella sbagliata resta sul campo',
    (tester) async {
      final gate = DemoSignupGateRepository(password: _club);
      await startAt(tester, gate, path: '/login');
      // Per accedere non serve: il campo c'è solo creando un account.
      expect(find.text('Password del club'), findsNothing);
      await openSignUp(tester);
      expect(find.text('Password del club'), findsOneWidget);

      await tester.enterText(labeledField('Email'), 'nuovo@example.com');
      await tester.enterText(
        labeledField('Password (almeno 8 caratteri)'),
        'milanac-2026',
      );
      // Senza: avviso, nessuna richiesta.
      await tester.ensureVisible(find.text('Crea il mio account'));
      await tester.tap(find.text('Crea il mio account'));
      await tester.pump();
      expect(
        find.text('Scrivi la password del club: te la dà il Direttivo.'),
        findsOneWidget,
      );
      await clearToast(tester);

      // Sbagliata: l'errore sta sul campo e l'account non si crea.
      final field = labeledField('Password del club');
      await tester.enterText(field, 'non-è-questa');
      await tester.tap(find.text('Crea il mio account'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: field, matching: find.text(wrongClubPasswordText)),
        findsOneWidget,
      );
      expect(find.text('Controlla la tua email'), findsNothing);
      expect(gate.approved, isEmpty);
      await clearToast(tester);

      // Giusta: via libera per quell'email e si passa alla conferma.
      await tester.enterText(field, _club);
      await tester.pump();
      expect(
        find.descendant(of: field, matching: find.text(wrongClubPasswordText)),
        findsNothing,
      );
      await tester.tap(find.text('Crea il mio account'));
      await tester.pumpAndSettle();
      expect(gate.approved, ['nuovo@example.com']);
      expect(find.text('Controlla la tua email'), findsOneWidget);
    },
  );

  testWidgets('Iscrizioni chiuse: niente modulo, ma chi ha un account accede', (
    tester,
  ) async {
    await startAt(
      tester,
      DemoSignupGateRepository(password: ''),
      path: '/login',
    );
    expect(find.text('Accedi'), findsOneWidget);
    await openSignUp(tester);
    expect(find.text('ISCRIZIONI CHIUSE'), findsOneWidget);
    expect(find.text('Crea il mio account'), findsNothing);
    expect(find.text('Password del club'), findsNothing);

    // Si torna all'accesso.
    await tester.ensureVisible(find.text('Accedi'));
    await tester.tap(find.text('Accedi'));
    await tester.pumpAndSettle();
    expect(find.text('Password dimenticata?'), findsOneWidget);
  });

  /// Passo 1 della registrazione, già compilato.
  Future<void> fillWho(WidgetTester tester) async {
    await tester.enterText(labeledField('Nome'), 'Mario');
    await tester.enterText(labeledField('Cognome'), 'Rossi');
    await tester.enterText(labeledField('Anno di nascita'), '1995');
    await tester.enterText(
      labeledField('Nome sulla maglia e sulla carta'),
      'ROSSI',
    );
  }

  /// Dal passo 2 fino a "Completa la registrazione".
  Future<void> finish(WidgetTester tester) async {
    final position = find.byType(DropdownButtonFormField<String>);
    await tester.scrollUntilVisible(
      position,
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('step-2')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(position);
    await tester.pumpAndSettle();
    await tester.tap(find.text(positionLabel('ATT')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completa la registrazione'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Registrazione di chi è entrato con Google: la password del club al passo 1',
    (tester) async {
      final container = await startAt(
        tester,
        DemoSignupGateRepository(mine: SignupStatus.password),
        path: '/registrazione',
      );
      final repo = container.read(
        registrationRepositoryProvider,
      ) as DemoRegistrationRepository..clubPassword = _club;
      expect(find.text('Password del club'), findsOneWidget);

      // Senza la password non si va avanti.
      await fillWho(tester);
      await tester.tap(find.text('Avanti'));
      await tester.pump();
      expect(
        find.text('Scrivi la password del club: te la dà il Direttivo.'),
        findsOneWidget,
      );
      expect(find.text('Passo 1 di 3'), findsOneWidget);
      await clearToast(tester);

      // Sbagliata: lo dice il server alla fine, e si torna al passo 1 sul campo.
      final field = labeledField('Password del club');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'non-è-questa');
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      expect(find.text('Passo 2 di 3'), findsOneWidget);
      await finish(tester);
      expect(find.text('Passo 1 di 3'), findsOneWidget);
      expect(
        find.descendant(of: field, matching: find.text(wrongClubPasswordText)),
        findsOneWidget,
      );
      expect(repo.last, isNull);
      await clearToast(tester);

      // Giusta: la registrazione arriva in fondo.
      await tester.enterText(field, _club);
      await tester.pump();
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completa la registrazione'));
      await tester.pumpAndSettle();
      expect(repo.last?.clubPassword, _club);
      expect(find.text('Ho letto e accetto'), findsOneWidget);
    },
  );

  testWidgets(
    'Registrazione con le iscrizioni chiuse: avviso, non si va avanti',
    (tester) async {
      await startAt(
        tester,
        DemoSignupGateRepository(mine: SignupStatus.closed),
        path: '/registrazione',
      );
      expect(find.text(signupsClosedText), findsOneWidget);
      expect(find.text('Password del club'), findsNothing);
      await fillWho(tester);
      await tester.tap(find.text('Avanti'));
      await tester.pump();
      expect(find.text('Passo 1 di 3'), findsOneWidget);
      expect(find.text(signupsClosedText), findsNWidgets(2));
      await clearToast(tester);
    },
  );

  testWidgets(
    'Impostazioni del Direttivo: imposta la password di iscrizione, poi chiude',
    (tester) async {
      final gate = DemoSignupGateRepository(password: '');
      await startAt(tester, gate);
      await goToSection(tester, 'Impostazioni');
      final row = find.text('Password di iscrizione');
      await tester.scrollUntilVisible(
        row,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Iscrizioni chiuse'), findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();
      // Niente da togliere finché non c'è.
      expect(find.text('Chiudi le iscrizioni'), findsNothing);
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), _club);
      await tester.enterText(fields.at(1), 'diversa-2026');
      await tester.tap(find.text('Salva'));
      await tester.pump();
      expect(find.text('Le due password non coincidono.'), findsOneWidget);
      expect(gate.password, '');
      await clearToast(tester);

      await tester.enterText(fields.at(1), _club);
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(gate.password, _club);
      expect(find.text('Impostata'), findsOneWidget);
      await clearToast(tester);

      // Tolta la password, le iscrizioni tornano chiuse.
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chiudi le iscrizioni'));
      await tester.pumpAndSettle();
      expect(gate.password, '');
      expect(find.text('Iscrizioni chiuse'), findsOneWidget);
      await clearToast(tester);
    },
  );

  test('risposte del server sullo stato delle iscrizioni', () {
    expect(signupStatusOf('password'), SignupStatus.password);
    expect(signupStatusOf('chiuse'), SignupStatus.closed);
    expect(signupStatusOf('aperte'), SignupStatus.open);
    expect(signupStatusOf('ok'), SignupStatus.open);
    expect(signupStatusOf(null), SignupStatus.open);
  });

  test('la password del club viaggia con la registrazione', () {
    RegistrationData data(String clubPassword) => RegistrationData(
      firstName: 'Mario',
      lastName: 'Rossi',
      cardName: 'ROSSI',
      birthYear: 1995,
      motto: '',
      direttivo: false,
      direttivoPassword: '',
      teams: const {Team.milanac},
      direttivoRoles: const [],
      fieldPosition: 'ATT',
      shirtNumber: 9,
      platform: null,
      clubPassword: clubPassword,
    );
    expect(data(_club).toParams()['p_club_password'], _club);
    expect(data('').toParams()['p_club_password'], '');
  });

  test('errori della password del club: tutti sul campo', () {
    expect(
      isClubPasswordError(const SignupGateError(wrongClubPasswordText)),
      isTrue,
    );
    expect(
      isClubPasswordError(
        const PostgrestException(
          message: 'Troppi tentativi con la password del club: riprova tra 15 minuti',
          code: 'P0001',
        ),
      ),
      isTrue,
    );
    expect(
      isClubPasswordError(
        const PostgrestException(
          message:
              'Per entrare nel club serve la password di iscrizione: chiedila '
              'al Direttivo',
          code: 'P0001',
        ),
      ),
      isTrue,
    );
    expect(
      isClubPasswordError(
        const PostgrestException(message: 'Nome non valido', code: 'P0001'),
      ),
      isFalse,
    );
    // Account fermato dal database (via libera scaduto): si spiega cosa fare.
    expect(
      friendlyAuthError(const AuthException('Database error saving new user')),
      contains('password del club'),
    );
  });

  test('indirizzo della web app per i link delle email', () {
    expect(
      webAppUrl(Uri.parse('https://milanacproclub.vercel.app/app/#/login?x=1')),
      'https://milanacproclub.vercel.app/app/',
    );
    expect(
      webAppUrl(Uri.parse('https://milanacproclub.vercel.app/app/?code=abc')),
      'https://milanacproclub.vercel.app/app/',
    );
    expect(
      webAppUrl(Uri.parse('http://localhost:8080')),
      'http://localhost:8080/',
    );
  });
}
