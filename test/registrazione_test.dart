import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/carta/card_stats.dart';
import 'package:milanac/features/carta/fut_card.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_reader.dart';
import 'package:milanac/features/registrazione/registration_page.dart';
import 'package:milanac/features/registrazione/registration_repository.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'labeled_field.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  Future<ProviderContainer> startAt(
    WidgetTester tester,
    String path, {
    Size size = const Size(1080, 2340),
    double ratio = 3,
    Profile? profile,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        if (profile != null)
          profileProvider.overrideWith((ref) => Stream.value(profile)),
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
    await tester.pumpAndSettle();
    container.read(routerProvider).go(path);
    await tester.pumpAndSettle();
    return container;
  }

  Finder listOf(int step) => find
      .descendant(
        of: find.byKey(ValueKey('step-$step')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scorre l'elenco del passo [step], dall'alto, finché [finder] è visibile.
  Future<void> reveal(WidgetTester tester, int step, Finder finder) async {
    tester.state<ScrollableState>(listOf(step)).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(finder, 150, scrollable: listOf(step));
    await tester.pumpAndSettle();
  }

  Future<void> clearToast(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
  }

  /// Passo 1 (i dati essenziali) compilato, poi la foto saltata: si arriva al passo 3.
  Future<void> toPlayer(WidgetTester tester) async {
    await tester.enterText(labeledField('Nome'), 'Mario');
    await tester.enterText(labeledField('Cognome'), 'Rossi');
    await tester.enterText(labeledField('Anno di nascita'), '1995');
    await next(tester);
    expect(find.text('Passo 2 di 3'), findsOneWidget);
    await next(tester);
    expect(find.text('Passo 3 di 3'), findsOneWidget);
  }

  Future<void> cardName(WidgetTester tester, String name) async {
    final field = labeledField('Nome sulla maglia e sulla carta');
    await reveal(tester, 3, field);
    await tester.enterText(field, name);
    await tester.pump();
  }

  Future<void> pickPosition(WidgetTester tester, String value) async {
    await reveal(tester, 3, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(positionLabel(value)).last);
    await tester.pumpAndSettle();
  }

  Future<void> complete(WidgetTester tester) async {
    await tester.tap(find.text('Completa la registrazione'));
    await tester.pumpAndSettle();
  }

  /// La carta dell'anteprima del passo 3 (sul telefono sta in testa all'elenco: si
  /// torna su per leggerla).
  Future<Member> preview(WidgetTester tester) async {
    tester.state<ScrollableState>(listOf(3)).position.jumpTo(0);
    await tester.pump();
    return tester.widget<FutCard>(find.byType(FutCard)).member;
  }

  /// L'overall scritto accanto ai pulsanti meno e più, e il livello della carta a parole.
  Future<(String?, String?)> overallShown(WidgetTester tester) async {
    await reveal(tester, 3, find.byKey(const ValueKey('overall-livello')));
    String? text(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data;
    return (text('overall-valore'), text('overall-livello'));
  }

  Future<void> slideOverall(WidgetTester tester, int value) async {
    final slider = find.byKey(const ValueKey('overall'));
    await reveal(tester, 3, slider);
    tester.widget<Slider>(slider).onChanged!(value.toDouble());
    await tester.pump();
  }

  DemoRegistrationRepository repoOf(ProviderContainer container) =>
      container.read(registrationRepositoryProvider)
          as DemoRegistrationRepository;

  testWidgets(
    'Registrazione: i dati essenziali, la foto, il giocatore con overall e '
    'stile; poi il regolamento da accettare',
    (tester) async {
      final container = await startAt(tester, '/registrazione');
      expect(find.text('Passo 1 di 3'), findsOneWidget);
      for (final title in ['I tuoi dati', 'La tua foto', 'Il tuo giocatore']) {
        expect(find.text(title), findsOneWidget);
      }

      // Passo 1: solo l'essenziale (il nome sulla carta arriva con il giocatore). Nome
      // e cognome arrivano dall'account; senza l'anno non si va avanti.
      expect(labeledField('Nome sulla maglia e sulla carta'), findsNothing);
      expect(find.text('Scegli dalla galleria'), findsNothing);
      await tester.tap(find.text('Avanti'));
      await tester.pump();
      expect(find.text('Scrivi il tuo anno di nascita.'), findsOneWidget);
      await clearToast(tester);
      await tester.enterText(labeledField('Nome'), 'Mario');
      await tester.enterText(labeledField('Cognome'), 'Rossi');
      await tester.enterText(labeledField('Anno di nascita'), '1995');
      await next(tester);

      // Passo 2: la foto, niente volto disegnato. Si può caricare anche dopo.
      expect(find.text('Passo 2 di 3'), findsOneWidget);
      expect(find.text('LA TUA FOTO'), findsOneWidget);
      expect(find.text('Scegli dalla galleria'), findsOneWidget);
      expect(find.text('A caso'), findsNothing);
      await next(tester);

      // Passo 3: il giocatore. Senza nome sulla carta e ruolo non si completa.
      expect(find.text('Passo 3 di 3'), findsOneWidget);
      expect(find.text('IL TUO GIOCATORE'), findsOneWidget);
      // In demo il nome arriva già dall'account: lo si toglie.
      await cardName(tester, '');
      await tester.tap(find.text('Completa la registrazione'));
      await tester.pump();
      expect(
        find.text('Scegli il nome da mettere sulla carta.'),
        findsOneWidget,
      );
      await clearToast(tester);
      await cardName(tester, 'Il Diavolo');
      await tester.tap(find.text('Completa la registrazione'));
      await tester.pump();
      expect(find.text('Scegli il tuo ruolo in campo.'), findsOneWidget);
      await clearToast(tester);
      await pickPosition(tester, 'ATT');

      // Overall: parte da quello proposto, si regola con meno e più.
      expect((await preview(tester)).overall, registrationStartingOverall);
      await reveal(tester, 3, find.byTooltip('Alza l\'overall'));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Alza l\'overall'));
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Abbassa l\'overall'));
      await tester.pump();
      expect(
        (await overallShown(tester)).$1,
        '${registrationStartingOverall + 2}',
      );
      expect(
        find.textContaining('Il Direttivo lo vede e può correggerlo'),
        findsOneWidget,
      );

      // Stile di gioco: un archetipo, con cosa fa.
      await reveal(tester, 3, find.text('Finalizzatore'));
      await tester.tap(find.text('Finalizzatore'));
      await tester.pumpAndSettle();

      // Direttivo con password e ruoli (le etichette lunghe vanno a capo).
      await reveal(tester, 3, find.text('MILANAC FUTURO'));
      await tester.tap(find.text('MILANAC FUTURO'));
      await reveal(tester, 3, find.text('Direttivo'));
      await tester.tap(find.text('Direttivo'));
      await tester.pumpAndSettle();
      await reveal(tester, 3, labeledField('Password del Direttivo'));
      await tester.enterText(
        labeledField('Password del Direttivo'),
        DemoRegistrationRepository.direttivoPassword,
      );
      await reveal(tester, 3, find.text('Resp. Comunicazioni e Marketing'));
      await tester.tap(find.text('Resp. Comunicazioni e Marketing'));
      await reveal(tester, 3, find.text('Capitano'));
      await tester.tap(find.text('Capitano'));
      await tester.pumpAndSettle();
      await complete(tester);

      final sent = repoOf(container).last!;
      expect(sent.firstName, 'Mario');
      expect(sent.cardName, 'Il Diavolo');
      expect(sent.birthYear, 1995);
      expect(sent.direttivo, isTrue);
      expect(
        sent.direttivoPassword,
        DemoRegistrationRepository.direttivoPassword,
      );
      expect(sent.direttivoRoles, [
        DirettivoRole.capitano,
        DirettivoRole.comunicazione,
      ]);
      expect(sent.toParams()['p_direttivo_roles'], [
        'capitano',
        'comunicazione',
      ]);
      expect(sent.fieldPosition, 'ATT');
      expect(sent.toParams()['p_face'], isNull);
      expect(sent.overall, registrationStartingOverall + 2);
      expect(sent.playStyle, 'Finalizzatore');
      expect(sent.toParams()['p_overall'], registrationStartingOverall + 2);
      expect(sent.toParams()['p_play_style'], 'Finalizzatore');

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
      expect(
        find.text('Scorri fino in fondo per poter accettare'),
        findsNothing,
      );

      await tester.tap(find.text('Ho letto e accetto'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Servono 2 minuti di lettura'),
        findsOneWidget,
      );
      expect(find.text('MILANAC PRO CLUB'), findsNothing);

      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ho letto e accetto'));
      await tester.pumpAndSettle();
      expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    },
  );

  testWidgets('Passo 3: la carta si compone mentre si sceglie (nome, overall, '
      'ruolo, livello)', (tester) async {
    await startAt(tester, '/registrazione');
    await toPlayer(tester);

    // Senza nome: il segnaposto, l'overall proposto, la carta del suo livello.
    await cardName(tester, '');
    expect((await preview(tester)).displayName, 'IL TUO NOME');
    expect((await preview(tester)).overall, registrationStartingOverall);
    expect(await overallShown(tester), (
      '$registrationStartingOverall',
      'Carta ${tierOf(registrationStartingOverall).label}',
    ));

    await cardName(tester, 'Rossi');
    expect((await preview(tester)).displayName, 'Rossi');
    await pickPosition(tester, 'POR');
    expect((await preview(tester)).fieldPosition, 'POR');

    // La barra porta l'overall al massimo: la carta diventa rossonera.
    await slideOverall(tester, overallMax);
    expect((await preview(tester)).overall, overallMax);
    expect(await overallShown(tester), ('$overallMax', 'Carta Rossonera'));
    expect(find.byTooltip('Alza l\'overall'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_rounded),
          )
          .onPressed,
      isNull,
      reason: 'oltre il massimo non si sale',
    );

    // E al minimo: bronzo, e non si scende oltre.
    await slideOverall(tester, overallMin);
    expect((await preview(tester)).overall, overallMin);
    expect(await overallShown(tester), ('$overallMin', 'Carta Bronzo'));
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.remove_rounded),
          )
          .onPressed,
      isNull,
    );

    // Lo stile si toglie con un secondo tocco.
    await reveal(tester, 3, find.text('Regista'));
    await tester.tap(find.text('Regista'));
    await tester.pumpAndSettle();
    expect((await preview(tester)).playStyle, 'Regista');
    await reveal(tester, 3, find.text('Regista'));
    await tester.tap(find.text('Regista'));
    await tester.pumpAndSettle();
    expect((await preview(tester)).playStyle, isNull);
  });

  testWidgets('Giocatore: una sola squadra, niente password; senza toccare '
      'overall e stile parte quello proposto', (tester) async {
    final container = await startAt(tester, '/registrazione');
    await tester.enterText(labeledField('Nome'), 'Luca');
    await tester.enterText(labeledField('Cognome'), 'Bianchi');
    await tester.enterText(labeledField('Anno di nascita'), '2000');
    await next(tester);
    await next(tester);
    expect(find.text('Password del Direttivo'), findsNothing);

    await cardName(tester, 'BIANCHI');
    await pickPosition(tester, 'DC');
    // Da giocatore le squadre si escludono: scegliere Futuro toglie MILANAC.
    await reveal(tester, 3, find.text('MILANAC FUTURO'));
    await tester.tap(find.text('MILANAC FUTURO'));
    await complete(tester);
    final sent = repoOf(container).last!;
    expect(sent.direttivo, isFalse);
    expect(sent.teams, {Team.futuro});
    expect(sent.fieldPosition, 'DC');
    expect(sent.overall, registrationStartingOverall);
    expect(sent.playStyle, isNull);
    expect(sent.toParams()['p_play_style'], isNull);
  });

  testWidgets('Indietro di Android: al passo precedente, non fuori dall\'app', (
    tester,
  ) async {
    await startAt(tester, '/registrazione');
    await toPlayer(tester);
    await cardName(tester, 'ROSSI');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Passo 2 di 3'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Passo 1 di 3'), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);

    // Tornando avanti quello che era scritto c'è ancora.
    await next(tester);
    await next(tester);
    expect((await preview(tester)).displayName, 'ROSSI');
  });

  testWidgets(
    'Password del Direttivo sbagliata: si resta al passo 3 con il campo evidenziato',
    (tester) async {
      final container = await startAt(tester, '/registrazione');
      await toPlayer(tester);
      await cardName(tester, 'ROSSI');
      await pickPosition(tester, 'ATT');
      await reveal(tester, 3, find.text('Direttivo'));
      await tester.tap(find.text('Direttivo'));
      await tester.pumpAndSettle();
      final field = labeledField('Password del Direttivo');
      await reveal(tester, 3, field);
      await tester.enterText(field, 'sbagliata');
      await reveal(tester, 3, find.text('Capitano'));
      await tester.tap(find.text('Capitano'));
      await complete(tester);

      expect(find.text('Passo 3 di 3'), findsOneWidget);
      await reveal(tester, 3, field);
      expect(
        find.descendant(
          of: field,
          matching: find.text('Password del Direttivo non corretta'),
        ),
        findsOneWidget,
      );
      final repo = repoOf(container);
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
      await clearToast(tester);
      await complete(tester);
      expect(repo.last?.direttivo, isTrue);
      expect(find.text('Ho letto e accetto'), findsOneWidget);
    },
  );

  testWidgets('Registrazione ripresa a metà: i dati già scritti si ritrovano, '
      'overall compreso', (tester) async {
    final container = await startAt(
      tester,
      '/registrazione',
      profile: const Profile(
        id: 'demo',
        displayName: 'IL BOMBER',
        role: ClubRole.pending,
        firstName: 'Paolo',
        lastName: 'Verdi',
        birthYear: 1993,
        motto: 'Sempre avanti',
        fieldPosition: 'COC',
        shirtNumber: 10,
        platform: 'pc',
        overall: 88,
      ),
    );
    expect(find.text('Paolo'), findsOneWidget);
    expect(find.text('Verdi'), findsOneWidget);
    expect(find.text('1993'), findsOneWidget);
    await next(tester);
    await next(tester);
    expect((await preview(tester)).displayName, 'IL BOMBER');
    expect((await preview(tester)).overall, 88);
    expect((await preview(tester)).fieldPosition, 'COC');
    expect((await preview(tester)).shirtNumber, 10);
    expect((await preview(tester)).platform, GamePlatform.pc);
    expect(await overallShown(tester), ('88', 'Carta Rossonera'));
    await complete(tester);
    final sent = repoOf(container).last!;
    expect(sent.cardName, 'IL BOMBER');
    expect(sent.motto, 'Sempre avanti');
    expect(sent.overall, 88);
    expect(sent.shirtNumber, 10);
  });

  testWidgets('Passo 3 su telefono stretto e su schermo largo: niente fuori '
      'misura, la carta accanto ai campi sul PC', (tester) async {
    // Telefono stretto (360 punti): la carta sta in testa all'elenco.
    await startAt(
      tester,
      '/registrazione',
      size: const Size(360, 640),
      ratio: 1,
    );
    await toPlayer(tester);
    final list = find.byKey(const ValueKey('step-3'));
    expect(
      find.descendant(of: list, matching: find.byType(FutCard)),
      findsOneWidget,
    );
    await cardName(tester, 'IL DIAVOLO 10');
    await reveal(tester, 3, find.text('Direttivo'));
    await tester.tap(find.text('Direttivo'));
    await tester.pumpAndSettle();
    await reveal(tester, 3, find.text('Il tuo motto (facoltativo)'));
    expect(tester.takeException(), isNull);

    // Schermo largo: la carta resta ferma a sinistra, fuori dall'elenco che scorre.
    tester.view.physicalSize = const Size(1366, 768);
    await tester.pumpAndSettle();
    expect(find.text('Passo 3 di 3'), findsOneWidget);
    expect((await preview(tester)).displayName, 'IL DIAVOLO 10');
    final wideList = find.byKey(const ValueKey('step-3'));
    expect(
      find.descendant(of: wideList, matching: find.byType(FutCard)),
      findsNothing,
    );
    expect(
      tester.getRect(find.byType(FutCard)).right,
      lessThanOrEqualTo(tester.getRect(wideList).left),
    );
    await reveal(tester, 3, find.text('Il tuo motto (facoltativo)'));
    expect(find.byType(FutCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('i parametri per il server: overall e stile in più, facoltativi', () {
    const data = RegistrationData(
      firstName: 'Mario',
      lastName: 'Rossi',
      birthYear: 1995,
      cardName: 'ROSSI',
      motto: null,
      teams: {Team.milanac},
      direttivo: false,
      direttivoPassword: null,
      direttivoRoles: [],
      fieldPosition: 'ATT',
      shirtNumber: 9,
      platform: null,
    );
    // Senza overall e stile (come le app di prima) il server mette i suoi valori.
    expect(data.toParams()['p_overall'], isNull);
    expect(data.toParams()['p_play_style'], isNull);
    expect(data.toParams().keys, containsAll(['p_overall', 'p_play_style']));
  });

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
