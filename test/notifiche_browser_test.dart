import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/core/push/browser_notifications.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/core/push/web_push.dart';
import 'package:milanac/features/impostazioni/impostazioni_page.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

/// Un browser finto: il permesso, l'iscrizione e gli avvisi del service worker.
class _FakeBrowser implements WebPushClient {
  _FakeBrowser(this.permission);

  @override
  WebPushPermission permission;

  /// Cosa risponde l'utente alla richiesta del browser.
  WebPushPermission answer = WebPushPermission.granted;
  WebPushSubscription? subscription;

  /// Le chiavi con cui è stata chiesta l'iscrizione, in ordine.
  final enabled = <String>[];
  var _count = 0;
  final incoming = StreamController<WebPushMessage>.broadcast();

  @override
  Future<WebPushSubscription> enable(String publicKey) async {
    enabled.add(publicKey);
    if (permission == WebPushPermission.ask) permission = answer;
    if (permission != WebPushPermission.granted) {
      throw const WebPushException('NEGATE');
    }
    return subscription ??= WebPushSubscription(
      endpoint: 'https://fcm.googleapis.com/fcm/send/${++_count}',
      p256dh: 'P',
      auth: 'A',
    );
  }

  @override
  Future<WebPushSubscription?> current() async => subscription;

  @override
  Future<String?> disable() async {
    final endpoint = subscription?.endpoint;
    subscription = null;
    return endpoint;
  }

  @override
  Stream<WebPushMessage> get messages => incoming.stream;
}

/// Il server finto: la chiave pubblica del club e le iscrizioni registrate.
class _FakeServer implements WebPushRepository {
  String? key = 'CHIAVE';
  bool online = true;
  final rows = <String>{};

  void _net() {
    if (!online) throw Exception('SocketException: rete assente');
  }

  @override
  Future<String?> publicKey() async {
    _net();
    return key;
  }

  @override
  Future<void> register(WebPushSubscription subscription) async {
    _net();
    rows.add(subscription.endpoint);
  }

  @override
  Future<void> remove(String endpoint) async {
    _net();
    rows.remove(endpoint);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  late _FakeBrowser browser;
  late _FakeServer server;
  late MemoryFlags flags;

  ProviderContainer start(WebPushPermission permission) {
    browser = _FakeBrowser(permission);
    server = _FakeServer();
    flags = MemoryFlags();
    final container = ProviderContainer(
      overrides: [
        webPushClientProvider.overrideWithValue(browser),
        webPushRepositoryProvider.overrideWithValue(server),
        localFlagsProvider.overrideWithValue(flags),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  BrowserNotifications notifier(ProviderContainer c) =>
      c.read(browserNotificationsProvider.notifier);
  BrowserPushStatus status(ProviderContainer c) =>
      c.read(browserNotificationsProvider);

  test('permesso già dato: all\'ingresso il browser si iscrive da solo con la '
      'chiave del club', () async {
    final c = start(WebPushPermission.granted);
    expect(status(c), BrowserPushStatus.off);
    await notifier(c).sync();
    expect(status(c), BrowserPushStatus.on);
    expect(browser.enabled, ['CHIAVE']);
    expect(server.rows, {'https://fcm.googleapis.com/fcm/send/1'});
  });

  test('spente da Impostazioni: via riga e iscrizione, e non si riaccendono da sole', () async {
    final c = start(WebPushPermission.granted);
    await notifier(c).sync();
    await notifier(c).turnOff();
    expect(status(c), BrowserPushStatus.off);
    expect(server.rows, isEmpty);
    expect(browser.subscription, isNull);

    // Al prossimo ingresso restano spente: nessuna nuova iscrizione.
    await notifier(c).sync();
    expect(status(c), BrowserPushStatus.off);
    expect(browser.enabled, hasLength(1));

    // Riaccese a mano tornano attive, e da lì in poi di nuovo da sole.
    expect(await notifier(c).turnOn(), isNull);
    expect(status(c), BrowserPushStatus.on);
    expect(server.rows, hasLength(1));
    expect(flags.values[BrowserNotifications.offKey], 'no');
  });

  test('uscita dall\'account: questo browser non riceve più, al rientro si '
      'iscrive di nuovo', () async {
    final c = start(WebPushPermission.granted);
    await notifier(c).sync();
    await notifier(c).release();
    expect(status(c), BrowserPushStatus.off);
    expect(server.rows, isEmpty);
    expect(browser.subscription, isNull);

    await notifier(c).sync();
    expect(status(c), BrowserPushStatus.on);
    expect(server.rows, {'https://fcm.googleapis.com/fcm/send/2'});
  });

  test('uscita senza rete: l\'iscrizione del browser si toglie lo stesso (la '
      'riga la toglierà il server al primo invio)', () async {
    final c = start(WebPushPermission.granted);
    await notifier(c).sync();
    server.online = false;
    await notifier(c).release();
    expect(browser.subscription, isNull);
    expect(server.rows, hasLength(1));
    expect(status(c), BrowserPushStatus.off);
  });

  test('server senza chiavi: le notifiche risultano non disponibili', () async {
    final c = start(WebPushPermission.ask);
    server.key = null;
    await notifier(c).sync();
    expect(status(c), BrowserPushStatus.unavailable);
    expect(await notifier(c).turnOn(), BrowserNotifications.unavailableMessage);
    expect(browser.enabled, isEmpty);

    // Appena le chiavi ci sono, si possono accendere.
    server.key = 'CHIAVE';
    await notifier(c).sync();
    expect(status(c), BrowserPushStatus.off);
    expect(await notifier(c).turnOn(), isNull);
    expect(status(c), BrowserPushStatus.on);
  });

  test('permesso negato alla richiesta del browser: si dice come '
      'sbloccarle', () async {
    final c = start(WebPushPermission.ask);
    flags.values[BrowserNotifications.askedKey] = 'si';
    await notifier(c).sync();
    browser.answer = WebPushPermission.denied;
    expect(await notifier(c).turnOn(), BrowserNotifications.deniedMessage);
    expect(status(c), BrowserPushStatus.denied);
    expect(server.rows, isEmpty);

    // Sbloccate dalle impostazioni del browser: riaprendo Impostazioni si iscrive.
    browser.permission = WebPushPermission.granted;
    notifier(c).refresh();
    await notifier(c).sync();
    expect(status(c), BrowserPushStatus.on);
  });

  test('il browser rinnova l\'iscrizione: viene registrata di nuovo', () async {
    final c = start(WebPushPermission.granted);
    await notifier(c).sync();
    browser.subscription = const WebPushSubscription(
      endpoint: 'https://fcm.googleapis.com/fcm/send/nuova',
      p256dh: 'P',
      auth: 'A',
    );
    browser.incoming.add(const WebPushMessage(WebPushMessageKind.resubscribed));
    await pumpEventQueue();
    await notifier(c).sync();
    expect(server.rows, contains('https://fcm.googleapis.com/fcm/send/nuova'));
  });

  test(
    'browser senza notifiche e iPhone da installare: niente chiamate',
    () async {
      for (final (permission, expected) in [
        (WebPushPermission.unsupported, BrowserPushStatus.unsupported),
        (WebPushPermission.needsInstall, BrowserPushStatus.needsInstall),
      ]) {
        final c = start(permission);
        server.online = false;
        await notifier(c).sync();
        expect(status(c), expected);
        expect(browser.enabled, isEmpty);
      }
    },
  );

  group('con la pagina aperta', () {
    Future<ProviderContainer> page(
      WidgetTester tester,
      WebPushPermission permission,
    ) async {
      final c = start(permission);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            scaffoldMessengerKey: messengerKey,
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      return c;
    }

    testWidgets('mai chiesto: la proposta esce una volta sola, e "Attiva" '
        'iscrive il browser', (tester) async {
      final c = await page(tester, WebPushPermission.ask);
      await notifier(c).sync();
      await tester.pumpAndSettle();
      expect(find.text(BrowserNotifications.proposal), findsOneWidget);
      expect(status(c), BrowserPushStatus.off);
      expect(browser.enabled, isEmpty);

      await tester.tap(find.text('Attiva'));
      await tester.pumpAndSettle();
      expect(status(c), BrowserPushStatus.on);
      expect(server.rows, hasLength(1));
      expect(find.text(BrowserNotifications.enabledMessage), findsOneWidget);

      // Rientrando (stesso browser) la proposta non torna.
      messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();
      await notifier(c).release();
      browser.permission = WebPushPermission.ask;
      await notifier(c).sync();
      await tester.pumpAndSettle();
      expect(find.text(BrowserNotifications.proposal), findsNothing);
    });

    testWidgets(
      'notifica con l\'app davanti: avviso in basso con "Apri"; clic su '
      'una notifica di sistema: si apre la sezione',
      (tester) async {
        final opened = <String>[];
        PushService.instance.onOpenRoute = opened.add;
        addTearDown(() {
          PushService.instance.onOpenRoute = null;
          PushService.instance.shouldShowInApp = null;
        });
        final c = await page(tester, WebPushPermission.granted);
        await notifier(c).sync();

        browser.incoming.add(
          const WebPushMessage(
            WebPushMessageKind.notification,
            title: 'Generale',
            body: 'Luca: stasera alle 21',
            route: '/chat/generale',
            data: {'channel': 'generale'},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Generale\nLuca: stasera alle 21'), findsOneWidget);
        await tester.tap(find.text('Apri'));
        await tester.pumpAndSettle();
        expect(opened, ['/chat/generale']);

        // Il canale già aperto non avvisa (come sul telefono).
        PushService.instance.shouldShowInApp = (data) =>
            data['channel'] != 'generale';
        browser.incoming.add(
          const WebPushMessage(
            WebPushMessageKind.notification,
            title: 'Generale',
            body: 'Secondo messaggio',
            route: '/chat/generale',
            data: {'channel': 'generale'},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Secondo messaggio'), findsNothing);

        browser.incoming.add(
          const WebPushMessage(WebPushMessageKind.open, route: '/presenze'),
        );
        await tester.pumpAndSettle();
        expect(opened, ['/chat/generale', '/presenze']);
      },
    );
  });

  group('Impostazioni', () {
    Future<void> openSettings(
      WidgetTester tester, {
      WebPushPermission? permission,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final ProviderContainer container;
      if (permission == null) {
        container = ProviderContainer();
        addTearDown(container.dispose);
      } else {
        container = start(permission);
        // La proposta all'ingresso è già stata vista: qui si prova l'interruttore.
        flags.values[BrowserNotifications.askedKey] = 'si';
      }
      container.read(introDoneProvider.notifier).complete();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MilanacApp(),
        ),
      );
      await tester.pumpAndSettle();
      await goToSection(tester, 'Impostazioni');
    }

    testWidgets('sul telefono la voce del browser non c\'è', (tester) async {
      await openSettings(tester);
      expect(find.text('NOTIFICHE'), findsOneWidget);
      expect(find.text('Notifiche in questo browser'), findsNothing);
    });

    testWidgets('nel browser: l\'interruttore accende e spegne le notifiche', (
      tester,
    ) async {
      await openSettings(tester, permission: WebPushPermission.ask);
      final row = find.widgetWithText(
        SwitchListTile,
        'Notifiche in questo browser',
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(find.text(browserPushHint(BrowserPushStatus.off)), findsOneWidget);
      expect(tester.widget<SwitchListTile>(row).value, isFalse);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(row).value, isTrue);
      expect(find.text(browserPushHint(BrowserPushStatus.on)), findsOneWidget);
      expect(server.rows, hasLength(1));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(row).value, isFalse);
      expect(server.rows, isEmpty);
      expect(browser.subscription, isNull);
    });

    testWidgets('permesso bloccato nel browser: interruttore fermo e '
        'spiegazione', (tester) async {
      await openSettings(tester, permission: WebPushPermission.denied);
      final row = find.widgetWithText(
        SwitchListTile,
        'Notifiche in questo browser',
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(row).onChanged, isNull);
      expect(
        find.text(browserPushHint(BrowserPushStatus.denied)),
        findsOneWidget,
      );
    });
  });
}
