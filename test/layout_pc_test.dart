import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/clock.dart';
import 'package:milanac/features/carta/mini_card.dart';
import 'package:milanac/features/chat/channel_page.dart';
import 'package:milanac/features/chat/chat_desktop.dart';
import 'package:milanac/features/chat/chat_list_page.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/home/home_page.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/voce/voice_room_sheet.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/app_shell.dart';
import 'package:milanac/shared/sections.dart';
import 'package:milanac/shared/side_menu.dart';
import 'package:milanac/shared/wide_layout.dart';

import 'chat_test.dart' show FakeVoiceRecorder, searchFor;
import 'helpers.dart';
import 'home_test.dart' show todayAt;

/// Lo schermo di un portatile.
const laptop = Size(1366, 768);

/// L'app demo (intro già vista) in una finestra grande [size] punti logici.
Future<ProviderContainer> startApp(
  WidgetTester tester, {
  Size size = laptop,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      // Le 20 di oggi: i messaggi di esempio (di poche ore prima) sono sempre di oggi.
      clockProvider.overrideWithValue(() => todayAt(20)),
      voiceRecorderFactoryProvider.overrideWithValue(FakeVoiceRecorder.new),
    ],
  );
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Qualcosa dentro il menu laterale.
Finder inMenu(Finder what) =>
    find.descendant(of: find.byType(SideMenu), matching: what);

/// Sceglie una voce del menu laterale.
Future<void> tapMenu(WidgetTester tester, MainTab tab) async {
  await tester.tap(inMenu(find.text(tab.label)));
  await tester.pumpAndSettle();
}

/// La scheda evidenziata nel menu laterale.
MainTab currentTab(WidgetTester tester) =>
    tester.widget<SideMenu>(find.byType(SideMenu)).current;

/// Cambia la dimensione della finestra (come trascinandone il bordo).
Future<void> resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('La soglia del layout da PC è una sola', () {
    expect(wideLayoutMinWidth, 1000);
    // Fino alla colonna dei telefoni e dei tablet le carte restano tre per riga.
    expect(MiniCardGrid.columnsFor(328), 3);
    expect(MiniCardGrid.columnsFor(ContentWidth.maxWidth), 3);
    expect(MiniCardGrid.columnsFor(1048), 5);
    expect(MiniCardGrid.columnsFor(3000), 6);
  });

  testWidgets('Schermo largo: menu laterale al posto della barra in basso, con '
      'stemma, schede, non letti e profilo', (tester) async {
    await startApp(tester);

    final menu = find.byType(SideMenu);
    expect(menu, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // A sinistra, alto quanto la finestra.
    expect(tester.getTopLeft(menu), Offset.zero);
    expect(tester.getSize(menu), Size(SideMenu.width, laptop.height));

    // Stemma e nome del club in alto, poi le cinque schede.
    expect(
      inMenu(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('stemma'),
        ),
      ),
      findsOneWidget,
    );
    expect(inMenu(find.text('MILANAC')), findsOneWidget);
    expect(inMenu(find.text('PRO CLUB')), findsOneWidget);
    for (final t in MainTab.values) {
      expect(inMenu(find.text(t.label)), findsOneWidget);
    }
    expect(currentTab(tester), MainTab.home);
    // I non letti sulla Chat (2 in Generale + 1 in MILANAC), come nella barra.
    expect(inMenu(find.text('3')), findsOneWidget);
    expect(find.byTooltip('Chat, 3 messaggi nuovi'), findsOneWidget);

    // La barra in alto ha il titolo della sezione: stemma, nome del club e foto
    // stanno nel menu.
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('MILANAC PRO CLUB'), findsNothing);
    expect(find.byType(ProfileButton), findsNothing);
    expect(find.byTooltip('Notifiche'), findsOneWidget);

    // Il contenuto resta una colonna comoda al centro dello spazio accanto al menu.
    final home = find.byType(HomePage);
    expect(tester.getSize(home).width, ContentWidth.maxWidth);
    final free = laptop.width - SideMenu.width - ContentWidth.maxWidth;
    expect(tester.getTopLeft(home).dx, SideMenu.width + free / 2);

    // In fondo al menu: la tua foto apre il profilo, l'ingranaggio le impostazioni.
    expect(inMenu(find.text('Demo Direttivo')), findsOneWidget);
    await tester.tap(find.byTooltip('Il tuo profilo'));
    await tester.pumpAndSettle();
    expect(find.text('IL TUO PROFILO'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    await tester.tap(inMenu(find.byTooltip('Impostazioni')));
    await tester.pumpAndSettle();
    expect(find.text('IMPOSTAZIONI'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schermo largo: dal menu si passa da una sezione all\'altra e le '
      'carte della Rosa usano lo spazio in più', (tester) async {
    await startApp(tester);

    await tapMenu(tester, MainTab.presenze);
    expect(find.text('PRESENZE'), findsOneWidget);
    expect(currentTab(tester), MainTab.presenze);
    await tapMenu(tester, MainTab.partite);
    expect(find.text('PARTITE'), findsOneWidget);
    expect(currentTab(tester), MainTab.partite);
    await tapMenu(tester, MainTab.club);
    expect(find.text('CLUB'), findsOneWidget);
    expect(currentTab(tester), MainTab.club);

    // Dentro una sezione il menu resta e in alto c'è la freccia per tornare.
    await tester.tap(find.text('Rosa'));
    await tester.pumpAndSettle();
    expect(find.text('ROSA'), findsOneWidget);
    expect(find.byTooltip('Indietro'), findsOneWidget);
    expect(find.byType(SideMenu), findsOneWidget);
    expect(currentTab(tester), MainTab.club);
    // Cinque carte sulla stessa riga (sui telefoni sono tre).
    final cards = find.byType(MiniCard);
    expect(cards, findsNWidgets(5));
    final rows = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(rows, hasLength(1));
    // L'elenco, invece, resta una colonna leggibile.
    await tester.tap(find.byTooltip('Mostra come elenco'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.text('Marco Rossi')).width,
      lessThan(ContentWidth.maxWidth),
    );
    expect(
      tester.getTopLeft(find.text('DIRETTIVO')).dx,
      greaterThan(SideMenu.width + 200),
    );
    await tester.tap(find.byTooltip('Mostra come carte'));
    await tester.pumpAndSettle();

    // La voce della scheda già aperta riporta alla sua pagina iniziale.
    await tapMenu(tester, MainTab.club);
    expect(find.text('CLUB'), findsOneWidget);
    expect(find.text('ROSA'), findsNothing);
    // Indietro da un'altra scheda riporta alla Home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(currentTab(tester), MainTab.home);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schermo largo: chat a due colonne, con l\'elenco dei canali '
      'sempre visibile accanto alla conversazione', (tester) async {
    await startApp(tester);
    await tapMenu(tester, MainTab.chat);

    // L'elenco a sinistra e, finché non si sceglie un canale, l'invito a destra.
    final list = find.byType(ChatListPage);
    expect(find.byType(ChatDesktop), findsOneWidget);
    expect(tester.getSize(list).width, ChatDesktop.listWidth);
    expect(tester.getTopLeft(list).dx, SideMenu.width);
    expect(find.text('Scegli una conversazione'), findsOneWidget);
    expect(find.text('Generale'), findsOneWidget);
    expect(find.text('Comunicazioni'), findsOneWidget);

    // Un canale si apre a destra: menu ed elenco restano dove sono.
    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPage), findsOneWidget);
    expect(find.byType(SideMenu), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(currentTab(tester), MainTab.chat);
    expect(tester.getSize(list).width, ChatDesktop.listWidth);
    expect(tester.getTopLeft(list).dx, SideMenu.width);
    expect(find.text('Comunicazioni'), findsOneWidget);
    expect(find.text('Scegli una conversazione'), findsNothing);
    expect(find.text('Stasera tutti in lobby alle 21:15!'), findsNWidgets(2));
    // Niente freccia "Indietro": l'elenco è lì accanto.
    expect(find.byTooltip('Indietro'), findsNothing);
    final field = find.byType(TextField);
    expect(
      tester.getTopLeft(field).dx,
      greaterThan(SideMenu.width + ChatDesktop.listWidth),
    );
    // Letti i messaggi di Generale, sul menu resta quello di MILANAC.
    expect(inMenu(find.text('1')), findsOneWidget);
    // Gli avvisi in basso sono una striscia al centro, non larga quanto la finestra.
    await tester.tap(find.byTooltip('Ascolta il vocale'));
    await tester.pumpAndSettle();
    expect(find.text('Vocale non disponibile nella demo.'), findsOneWidget);
    final notice = find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first;
    expect(tester.getSize(notice).width, WideSnackBars.width);
    expect(tester.getCenter(notice).dx, closeTo(laptop.width / 2, 1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Invio manda il messaggio, come sempre con la tastiera del computer.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.enterText(field, 'Scritto dal PC');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('Scritto dal PC'), findsOneWidget);
    // Senza testo resta il microfono per i vocali.
    expect(
      find.bySemanticsLabel('Tieni premuto per registrare un vocale'),
      findsOneWidget,
    );

    // Un altro canale prende il posto del primo, senza pagine una sull'altra.
    await tester.tap(find.descendant(of: list, matching: find.text('MILANAC')));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPage), findsOneWidget);
    expect(find.text('La squadra MILANAC'), findsOneWidget);
    expect(find.text('Stasera provo la build nuova da DC'), findsOneWidget);
    expect(find.text('Stasera tutti in lobby alle 21:15!'), findsNothing);
    expect(inMenu(find.byType(Badge)), findsNothing);

    // La stanza vocale si apre a schermo intero e, chiusa, si torna alle colonne.
    await tester.tap(find.byTooltip('Stanza vocale'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceRoomPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(VoiceRoomPage), findsNothing);
    expect(find.byType(ChatDesktop), findsOneWidget);

    // La ricerca: il messaggio scelto la chiude e apre il suo canale a destra.
    await tester.tap(find.byTooltip('Cerca nei messaggi'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatSearchPage), findsOneWidget);
    await searchFor(tester, 'lobby');
    await tester.tap(
      find.textContaining('Stasera tutti in lobby', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatSearchPage), findsNothing);
    expect(find.byType(ChannelPage), findsOneWidget);
    expect(find.text('Tutto il club'), findsOneWidget);
    expect(find.text('Scritto dal PC'), findsOneWidget);

    // Indietro (del browser o del telefono) riporta all'elenco con l'invito.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPage), findsNothing);
    expect(find.text('Scegli una conversazione'), findsOneWidget);
    expect(currentTab(tester), MainTab.chat);

    // Dal menu, con una conversazione aperta, si va nelle altre sezioni.
    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    await tapMenu(tester, MainTab.presenze);
    expect(find.byType(ChannelPage), findsNothing);
    expect(find.text('PRESENZE'), findsOneWidget);
    expect(currentTab(tester), MainTab.presenze);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schermo largo: una conversazione aperta da una notifica ha '
      'menu ed elenco, e indietro porta alla Chat', (tester) async {
    await startApp(tester);
    await goToPath(tester, '/chat/milanac');

    expect(find.byType(SideMenu), findsOneWidget);
    expect(currentTab(tester), MainTab.chat);
    expect(find.byType(ChatListPage), findsOneWidget);
    expect(find.text('La squadra MILANAC'), findsOneWidget);
    expect(find.text('Stasera provo la build nuova da DC'), findsOneWidget);

    // Da lì si cambia canale e si torna all'elenco.
    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPage), findsOneWidget);
    expect(find.text('Tutto il club'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChannelPage), findsNothing);
    expect(find.text('Scegli una conversazione'), findsOneWidget);

    // Un canale che non c'è: l'avviso sta a destra, l'elenco resta.
    await goToPath(tester, '/chat/inesistente');
    expect(find.text('Canale non disponibile'), findsOneWidget);
    expect(find.byType(ChatListPage), findsOneWidget);
    await tester.tap(find.text('Torna alla chat'));
    await tester.pumpAndSettle();
    expect(find.text('Scegli una conversazione'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stringendo la finestra si torna al layout da telefono senza '
      'perdere quello che si stava scrivendo', (tester) async {
    await startApp(tester);
    await tapMenu(tester, MainTab.chat);
    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A metà frase');
    await tester.pump();

    // Sotto la soglia: conversazione a schermo intero, con la freccia per tornare.
    await resize(tester, const Size(700, 768));
    expect(find.byType(SideMenu), findsNothing);
    expect(find.byType(ChatListPage), findsNothing);
    expect(find.byTooltip('Indietro'), findsOneWidget);
    expect(find.text('A metà frase'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(ChatListPage), findsOneWidget);
    expect(find.byType(ChatDesktop), findsNothing);

    // Riallargando torna il menu, sulla stessa scheda.
    await resize(tester, laptop);
    expect(find.byType(NavigationBar), findsNothing);
    expect(currentTab(tester), MainTab.chat);
    expect(find.text('Scegli una conversazione'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Schermo largo: lavagna e stanza vocale restano al centro, senza '
      'comandi larghi quanto lo schermo', (tester) async {
    await startApp(tester);

    await goToPath(tester, '/lavagna');
    final board = find.byKey(const ValueKey('lavagna'));
    expect(tester.getCenter(board).dx, closeTo(laptop.width / 2, 1));
    // Gli strumenti in basso: sei pulsanti in una colonna al centro.
    final tools = [
      for (final label in ['Gettoni', 'Pallone', 'Fuoco', 'Freccia', 'Pulisci'])
        tester.getCenter(find.text(label)).dx,
    ];
    final margin = (laptop.width - ContentWidth.maxWidth) / 2;
    expect(tools.first, greaterThan(margin));
    expect(tools.last, lessThan(laptop.width - margin));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await goToPath(tester, '/chat/milanac');
    await tester.tap(find.byTooltip('Stanza vocale'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceRoomPage), findsOneWidget);
    // Chi è nella stanza sta in una colonna al centro, non ai lati dello schermo.
    final marco = tester.getCenter(find.text('Marco')).dx;
    final luca = tester.getCenter(find.text('Luca')).dx;
    expect(marco, greaterThan(laptop.width / 2 - 280));
    expect(luca, lessThan(laptop.width / 2 + 280));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 780), Size(999, 768)]) {
    testWidgets(
      'Sotto la soglia (${size.width.toInt()} punti) resta la barra in '
      'basso e la chat a schermo intero',
      (tester) async {
        await startApp(tester, size: size);

        expect(find.byType(SideMenu), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        // In alto lo stemma, il nome del club e la tua foto, come sempre.
        expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
        expect(find.text('HOME'), findsNothing);
        expect(find.byType(ProfileButton), findsOneWidget);
        // I non letti sulla scheda Chat della barra.
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        // Il contenuto non supera la colonna comoda di sempre.
        expect(
          tester.getSize(find.byType(HomePage)).width,
          size.width < ContentWidth.maxWidth
              ? size.width
              : ContentWidth.maxWidth,
        );

        await tapTab(tester, 'Chat');
        expect(find.byType(ChatDesktop), findsNothing);
        expect(find.text('CHAT'), findsOneWidget);
        expect(find.byTooltip('Cerca nei messaggi'), findsOneWidget);
        await tester.tap(find.text('Generale'));
        await tester.pumpAndSettle();
        // La conversazione copre tutto: niente elenco, niente barra, freccia indietro.
        expect(find.byType(ChannelPage), findsOneWidget);
        expect(find.byType(ChatListPage), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(SideMenu), findsNothing);
        await tester.tap(find.byTooltip('Indietro'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatListPage), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);

        // La Rosa: tre carte per riga.
        await goToPath(tester, '/rosa');
        final cards = find.byType(MiniCard);
        final firstRow = tester.getTopLeft(cards.first).dy;
        expect(
          cards.evaluate().where(
            (e) => tester.getTopLeft(find.byWidget(e.widget)).dy == firstRow,
          ),
          hasLength(3),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
