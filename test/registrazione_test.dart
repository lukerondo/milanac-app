import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/parchment.dart';
import 'package:milanac/features/registrazione/registration_repository.dart';
import 'package:milanac/features/volto/face.dart';
import 'package:milanac/main.dart';

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
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Registrazione in tre passi, poi il regolamento da accettare', (
    tester,
  ) async {
    final container = await startAt(tester, '/registrazione');
    expect(find.text('PASSO 1 DI 3 · CHI SEI'), findsOneWidget);

    // Nome e cognome arrivano dall'account; senza l'anno non si va avanti.
    await tester.tap(find.text('Avanti'));
    await tester.pump();
    expect(find.text('Scrivi il tuo anno di nascita.'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Mario');
    await tester.enterText(find.widgetWithText(TextField, 'Cognome'), 'Rossi');
    await tester.enterText(
      find.widgetWithText(TextField, 'Anno di nascita'),
      '1995',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome sulla maglia e sulla carta'),
      'Il Diavolo',
    );
    await tester.pump();
    expect(find.text('IL DIAVOLO'), findsOneWidget);
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('PASSO 2 DI 3 · SQUADRA E RUOLO'), findsOneWidget);

    // Direttivo con password e ruoli; ruolo in campo obbligatorio.
    await tester.tap(find.text('Milan AC Futuro'));
    await tester.tap(find.text('Faccio parte del Direttivo'));
    await tester.pumpAndSettle();
    expect(find.text('Password del Direttivo'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Password del Direttivo'),
      'milanac2026!',
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
    expect(find.text('PASSO 3 DI 3 · IL TUO VOLTO'), findsOneWidget);

    // Volto: a caso, poi una scelta precisa.
    await tester.tap(find.text('A caso'));
    await tester.pumpAndSettle();
    // Il nome dello stile compare anche nel riepilogo quando "A caso" lo sceglie:
    // si punta alla sola opzione.
    await reveal(tester, 3, find.widgetWithText(ChoiceChip, 'Ciuffo'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ciuffo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completa la registrazione'));
    await tester.pumpAndSettle();

    final sent = (container.read(
      registrationRepositoryProvider,
    ) as DemoRegistrationRepository).last!;
    expect(sent.firstName, 'Mario');
    expect(sent.cardName, 'Il Diavolo');
    expect(sent.birthYear, 1995);
    expect(sent.direttivo, isTrue);
    expect(sent.direttivoPassword, 'milanac2026!');
    expect(sent.direttivoRoles, hasLength(2));
    expect(sent.fieldPosition, 'ATT');
    expect(sent.face.hair, FacePart.hair.options.indexOf('Ciuffo'));

    // Regolamento: si accetta solo in fondo e dopo 2 minuti.
    expect(find.text('Ho letto e accetto'), findsOneWidget);
    expect(
      find.text('Scorri fino in fondo per poter accettare.'),
      findsOneWidget,
    );
    await tester.drag(
      find.descendant(
        of: find.byType(ParchmentSheet),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Scorri fino in fondo per poter accettare.'),
      findsNothing,
    );

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
    await startAt(tester, '/registrazione');
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Luca');
    await tester.enterText(
      find.widgetWithText(TextField, 'Cognome'),
      'Bianchi',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Anno di nascita'),
      '2000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome sulla maglia e sulla carta'),
      'BIANCHI',
    );
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('Password del Direttivo'), findsNothing);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byType(FilterChip), findsNothing);
  });
}
