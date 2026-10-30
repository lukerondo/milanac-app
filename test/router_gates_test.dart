import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/router.dart';

import 'helpers.dart';
import 'traguardi_walkout_test.dart' show startApp;

/// Un giocatore registrato, entrato nel club, con il regolamento n. 2 accettato.
const _player = Profile(
  id: 'p',
  displayName: 'Mario',
  role: ClubRole.giocatore,
  registrationCompleted: true,
  rulesAcceptedVersion: 2,
);

const _direttivo = Profile(
  id: 'd',
  displayName: 'Capo',
  role: ClubRole.direttivo,
  registrationCompleted: true,
);

String? gate(
  String loc, {
  AsyncValue<bool> session = const AsyncData(true),
  bool recovery = false,
  AsyncValue<Profile?> profile = const AsyncData(_player),
  AsyncValue<int?> rules = const AsyncData(2),
  bool writeLater = false,
}) => gateRedirect(
  loc: loc,
  session: session,
  passwordRecovery: recovery,
  profile: profile,
  rules: rules,
  rulesWriteLater: writeLater,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('porte del router (produzione)', () {
    test(
      'senza sessione si va all\'accesso; durante il caricamento si aspetta',
      () {
        expect(gate('/', session: const AsyncData(false)), '/login');
        expect(gate('/login', session: const AsyncData(false)), isNull);
        expect(gate('/', session: const AsyncLoading()), isNull);
      },
    );

    test('link della password dimenticata: prima la nuova password', () {
      expect(gate('/', recovery: true), '/nuova-password');
      expect(gate('/nuova-password', recovery: true), isNull);
    });

    test(
      'profilo che non si carica: "Nessuna connessione", non la registrazione',
      () {
        final offline = AsyncError<Profile?>(
          Exception('rete'),
          StackTrace.empty,
        );
        expect(gate('/', profile: offline), '/offline');
        expect(gate('/offline', profile: offline), isNull);
        // Primo caricamento: si aspetta.
        expect(gate('/', profile: const AsyncLoading()), isNull);
        // Appena il profilo arriva, dalla pagina offline si torna alla Home.
        expect(gate('/offline'), goHome);
      },
    );

    test(
      'nuovi tentativi dopo un errore: si resta su "Nessuna connessione"',
      () async {
        final c = ProviderContainer(
          retry: (_, _) => const Duration(milliseconds: 5),
        );
        addTearDown(c.dispose);
        final profile = FutureProvider<Profile?>(
          (ref) => Future.error(Exception('rete')),
        );
        c.listen(profile, (_, _) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final value = c.read(profile);
        expect(value.hasError, isTrue);
        expect(gate('/', profile: value), '/offline');
      },
    );

    test('registrazione, account sospeso e regolamento, in quest\'ordine', () {
      expect(gate('/', profile: const AsyncData(null)), '/registrazione');
      expect(
        gate(
          '/',
          profile: const AsyncData(
            Profile(id: 'n', displayName: 'Nuovo', role: ClubRole.pending),
          ),
        ),
        '/registrazione',
      );
      expect(
        gate(
          '/',
          profile: const AsyncData(
            Profile(
              id: 's',
              displayName: 'Sospeso',
              role: ClubRole.giocatore,
              active: false,
              registrationCompleted: true,
            ),
          ),
        ),
        '/attesa',
      );
      // Nuova versione del regolamento da accettare.
      expect(gate('/', rules: const AsyncData(3)), '/regolamento/accetta');
      // Registrato ma non ancora entrato nel club (in attesa): deve accettarlo.
      expect(
        gate(
          '/',
          profile: const AsyncData(
            Profile(
              id: 'a',
              displayName: 'Atteso',
              role: ClubRole.pending,
              registrationCompleted: true,
            ),
          ),
        ),
        '/regolamento/accetta',
      );
    });

    test('regolamento che non si carica: chi è in regola entra comunque', () {
      final err = AsyncError<int?>(Exception('rete'), StackTrace.empty);
      expect(gate('/', rules: err), isNull);
      expect(gate('/intro', rules: err), goHome);
      expect(gate('/', rules: const AsyncLoading()), isNull);
    });

    test(
      'primo regolamento: il Direttivo lo scrive, o più tardi dal promemoria',
      () {
        const none = AsyncData<int?>(null);
        expect(
          gate('/', profile: const AsyncData(_direttivo), rules: none),
          '/regolamento/scrivi',
        );
        // "Più tardi": niente porta, ma il promemoria della Sala Direttivo apre l'editor.
        expect(
          gate(
            '/',
            profile: const AsyncData(_direttivo),
            rules: none,
            writeLater: true,
          ),
          isNull,
        );
        expect(
          gate(
            '/regolamento/scrivi',
            profile: const AsyncData(_direttivo),
            rules: none,
            writeLater: true,
          ),
          isNull,
        );
        // Un giocatore non ci arriva; e a regolamento pubblicato l'editor iniziale chiude.
        expect(gate('/regolamento/scrivi', rules: none), goHome);
        expect(
          gate(
            '/regolamento/scrivi',
            profile: const AsyncData(
              Profile(
                id: 'd',
                displayName: 'Capo',
                role: ClubRole.direttivo,
                registrationCompleted: true,
                rulesAcceptedVersion: 2,
              ),
            ),
          ),
          goHome,
        );
      },
    );

    test('Sala Direttivo solo per il Direttivo; le porte superate tornano alla Home', () {
      expect(gate('/direttivo'), '/');
      expect(gate('/direttivo/stasera'), '/');
      expect(gate('/rosa'), isNull);
      expect(gate('/login'), goHome);
      expect(gate('/registrazione'), goHome);
    });
  });

  testWidgets('vecchi indirizzi delle notifiche: portano alla nuova sezione', (
    tester,
  ) async {
    await startApp(tester);
    await goToPath(tester, '/risultati');
    expect(find.text('PARTITE'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Partite'),
      ),
      findsOneWidget,
    );
    await goToPath(tester, '/carta');
    expect(find.text('IL TUO PROFILO'), findsOneWidget);
    await goToPath(tester, '/mondo?scheda=notizie');
    expect(find.text('MONDO PROCLUB'), findsOneWidget);
    // Sottosezione aperta da una notifica: indietro porta al Club, non fuori dall'app.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('CLUB'), findsOneWidget);
  });
}
