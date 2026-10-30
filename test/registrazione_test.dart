import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_reader.dart';
import 'package:milanac/features/registrazione/registration_page.dart';
import 'package:milanac/features/registrazione/registration_repository.dart';
import 'package:milanac/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'labeled_field.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startAt(WidgetTester tester, String path) async {
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
    container.read(routerProvider).go(path);
    await tester.pumpAndSettle();
    return container;
  }

  /// Scorre l'elenco del passo [step] finché [finder] è visibile.
  Future<void> reveal(WidgetTester tester, int step, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find
          .descendant(
            of: find.byKey(ValueKey('step-$step')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickPosition(WidgetTester tester, String value) async {
    await reveal(tester, 2, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(positionLabel(value)).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Registrazione in tre passi, poi il regolamento da accettare', (
    tester,
  ) async {
    final container = await startAt(tester, '/registrazione');
    expect(find.text('Passo 1 di 3'), findsOneWidget);

    // Nome e cognome arrivano dall'account; senza l'anno non si va avanti.
    await tester.tap(find.text('Avanti'));
    await tester.pump();
    expect(find.text('Scrivi il tuo anno di nascita.'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.enterText(labeledField('Nome'), 'Mario');
    await tester.enterText(labeledField('Cognome'), 'Rossi');
    await tester.enterText(labeledField('Anno di nascita'), '1995');
    await tester.enterText(
      labeledField('Nome sulla maglia e sulla carta'),
      'Il Diavolo',
    );
    await tester.pump();
    expect(find.text('IL DIAVOLO'), findsOneWidget);
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('Passo 2 di 3'), findsOneWidget);

    // Direttivo con password e ruoli; ruolo in campo obbligatorio.
    await tester.tap(find.text('Milan AC Futuro'));
    await tester.tap(find.text('Direttivo'));
    await tester.pumpAndSettle();
    expect(find.text('Password del Direttivo'), findsOneWidget);
    await tester.enterText(
      labeledField('Password del Direttivo'),
      DemoRegistrationRepository.direttivoPassword,
    );
    await reveal(tester, 2, find.text('Capitano'));
    await tester.tap(find.text('Capitano'));
    await tester.tap(find.text('Gestore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avanti'));
    await tester.pump();
    expect(find.text('Scegli il tuo ruolo in campo.'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await pickPosition(tester, 'ATT');
    await reveal(tester, 2, find.text('PlayStation 5'));
    await tester.tap(find.text('PlayStation 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('Passo 3 di 3'), findsOneWidget);

    // La foto: niente volto disegnato. Si può caricare anche dopo (sagoma grigia).
    expect(find.text('LA TUA FOTO'), findsOneWidget);
    expect(find.text('Scegli dalla galleria'), findsOneWidget);
    expect(find.text('A caso'), findsNothing);
    await tester.tap(find.text('Completa la registrazione'));
    await tester.pumpAndSettle();

    final sent = (container.read(
      registrationRepositoryProvider,
    ) as DemoRegistrationRepository).last!;
    expect(sent.firstName, 'Mario');
    expect(sent.cardName, 'Il Diavolo');
    expect(sent.birthYear, 1995);
    expect(sent.direttivo, isTrue);
    expect(
      sent.direttivoPassword,
      DemoRegistrationRepository.direttivoPassword,
    );
    expect(sent.direttivoRoles, hasLength(2));
    expect(sent.fieldPosition, 'ATT');
    expect(sent.toParams()['p_face'], isNull);

    // Regolamento: si accetta solo in fondo e dopo 2 minuti.
    expect(find.text('Ho letto e accetto'), findsOneWidget);
    expect(
      find.text('Scorri fino in fondo per poter accettare'),
      findsOneWidget,
    );
    await tester.drag(
      find.descendant(
        of: find.byType(RulesReader),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scorri fino in fondo per poter accettare'), findsNothing);

    await tester.tap(find.text('Ho letto e accetto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Servono 2 minuti di lettura'), findsOneWidget);
    expect(find.text('MILAN AC PRO CLUB'), findsNothing);

    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho letto e accetto'));
    await tester.pumpAndSettle();
    expect(find.text('MILAN AC PRO CLUB'), findsOneWidget);
  });

  testWidgets('Giocatore: una sola squadra, niente password', (tester) async {
    final container = await startAt(tester, '/registrazione');
    await tester.enterText(labeledField('Nome'), 'Luca');
    await tester.enterText(labeledField('Cognome'), 'Bianchi');
    await tester.enterText(labeledField('Anno di nascita'), '2000');
    await tester.enterText(
      labeledField('Nome sulla maglia e sulla carta'),
      'BIANCHI',
    );
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('Password del Direttivo'), findsNothing);

    // Da giocatore le squadre si escludono: scegliere Futuro toglie Milan AC.
    await tester.tap(find.text('Milan AC Futuro'));
    await pickPosition(tester, 'DC');
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completa la registrazione'));
    await tester.pumpAndSettle();
    final sent = (container.read(
      registrationRepositoryProvider,
    ) as DemoRegistrationRepository).last!;
    expect(sent.direttivo, isFalse);
    expect(sent.teams, {Team.futuro});
    expect(sent.fieldPosition, 'DC');
  });

  Future<void> fillWho(WidgetTester tester) async {
    await tester.enterText(labeledField('Nome'), 'Mario');
    await tester.enterText(labeledField('Cognome'), 'Rossi');
    await tester.enterText(labeledField('Anno di nascita'), '1995');
    await tester.enterText(
      labeledField('Nome sulla maglia e sulla carta'),
      'ROSSI',
    );
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
  }

  testWidgets('Indietro di Android: al passo precedente, non fuori dall\'app', (
    tester,
  ) async {
    await startAt(tester, '/registrazione');
    await fillWho(tester);
    expect(find.text('Passo 2 di 3'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Passo 1 di 3'), findsOneWidget);
    expect(find.text('ROSSI'), findsWidgets);
  });

  testWidgets(
    'Password del Direttivo sbagliata: si torna al passo 2 con il campo evidenziato',
    (tester) async {
      final container = await startAt(tester, '/registrazione');
      await fillWho(tester);
      await tester.tap(find.text('Direttivo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        labeledField('Password del Direttivo'),
        'sbagliata',
      );
      await reveal(tester, 2, find.text('Capitano'));
      await tester.tap(find.text('Capitano'));
      await pickPosition(tester, 'ATT');
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completa la registrazione'));
      await tester.pumpAndSettle();

      expect(find.text('Passo 2 di 3'), findsOneWidget);
      final field = labeledField('Password del Direttivo');
      expect(
        find.descendant(
          of: field,
          matching: find.text('Password del Direttivo non corretta'),
        ),
        findsOneWidget,
      );
      final repo = container.read(
        registrationRepositoryProvider,
      ) as DemoRegistrationRepository;
      expect(repo.last, isNull);

      // Corretta la password l'errore sparisce e la registrazione va a buon fine.
      await tester.enterText(
        field,
        DemoRegistrationRepository.direttivoPassword,
      );
      await tester.pump();
      expect(
        find.descendant(
          of: field,
          matching: find.text('Password del Direttivo non corretta'),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completa la registrazione'));
      await tester.pumpAndSettle();
      expect(repo.last?.direttivo, isTrue);
      expect(find.text('Ho letto e accetto'), findsOneWidget);
    },
  );

  test('troppi tentativi con la password: stesso trattamento della password errata', () {
    expect(
      isDirettivoPasswordError(
        const RegistrationError('Password del Direttivo non corretta'),
      ),
      isTrue,
    );
    expect(
      isDirettivoPasswordError(
        const PostgrestException(
          message: 'Troppi tentativi con la password del Direttivo: riprova tra 15 minuti',
          code: 'P0001',
        ),
      ),
      isTrue,
    );
    expect(
      isDirettivoPasswordError(
        const PostgrestException(message: 'Nome non valido', code: 'P0001'),
      ),
      isFalse,
    );
  });

  testWidgets(
    'Profilo non caricato: errore con Riprova, non la rotella infinita',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      var offline = true;
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(
            (ref) => offline
                ? Stream<Profile?>.error(
                    Exception('SocketException: Failed host lookup'),
                  )
                : Stream.value(Profile.demo),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(introDoneProvider.notifier).complete();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MilanacApp(),
        ),
      );
      container.read(routerProvider).go('/registrazione');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Nessuna connessione: controlla la rete e riprova.'),
        findsOneWidget,
      );
      expect(find.text('Passo 1 di 3'), findsNothing);

      offline = false;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Passo 1 di 3'), findsOneWidget);
    },
  );
}
