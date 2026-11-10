// Le notifiche nel browser: il lato Dart contro un `milanacNotifiche` finto (quello vero è
// web/notifiche.js, provato con il service worker in tools/web/test/notifiche_test.js).
// Gira solo in un browser:  flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/push/web_push.dart';
import 'package:milanac/core/push/web_push_web.dart';

@JS('eval')
external JSAny? _eval(String code);

@JS('prova')
external _Prova get _prova;

extension type _Prova._(JSObject _) implements JSObject {
  external JSArray<JSString> get chiamate;
  external set stato(String stato);
  external set esito(JSObject esito);
  external void avvisa(
    String tipo,
    String titolo,
    String corpo,
    String sezione,
    String dati,
  );
}

/// Un `milanacNotifiche` finto: ricorda le chiamate, risponde come deciso dal test e gli
/// lascia mandare gli avvisi del service worker.
void _fake() => _eval('''
  window.prova = {
    chiamate: [],
    stato: 'da_chiedere',
    esito: { errore: '', endpoint: 'https://fcm.googleapis.com/fcm/send/1', p256dh: 'P', auth: 'A' },
  };
  window.milanacNotifiche = {
    stato: function () { return prova.stato; },
    attiva: async function (chiave) { prova.chiamate.push('attiva ' + chiave); return prova.esito; },
    iscrizione: async function () { prova.chiamate.push('iscrizione'); return prova.esito; },
    disattiva: async function () { prova.chiamate.push('disattiva'); return prova.esito.endpoint; },
    ascolta: function (fn) { prova.chiamate.push('ascolta'); prova.avvisa = fn; },
  };
''');

JSObject _esito(String errore, String endpoint) => _eval(
  '({ errore: "$errore", endpoint: "$endpoint", p256dh: "P", auth: "A" })',
) as JSObject;

List<String> _calls() => [for (final c in _prova.chiamate.toDart) c.toDart];

void main() {
  setUp(_fake);

  test('lo stato del permesso, come lo dice lo script', () {
    final push = BrowserWebPush();
    for (final (stato, permission) in [
      ('da_chiedere', WebPushPermission.ask),
      ('concesse', WebPushPermission.granted),
      ('negate', WebPushPermission.denied),
      ('da_installare', WebPushPermission.needsInstall),
      ('non_supportate', WebPushPermission.unsupported),
    ]) {
      _prova.stato = stato;
      expect(push.permission, permission);
    }
  });

  test(
    'attiva: iscrive con la chiave del club e restituisce l\'iscrizione',
    () async {
      final push = BrowserWebPush();
      final sub = await push.enable('CHIAVE');
      expect(sub.endpoint, 'https://fcm.googleapis.com/fcm/send/1');
      expect((sub.p256dh, sub.auth), ('P', 'A'));
      expect(_calls(), ['ascolta', 'attiva CHIAVE']);

      final current = await push.current();
      expect(current?.endpoint, sub.endpoint);
      expect(await push.disable(), sub.endpoint);
    },
  );

  test(
    'permesso negato o errore del browser: eccezione con la sigla',
    () async {
      final push = BrowserWebPush();
      _prova.esito = _esito('NEGATE', '');
      await expectLater(
        push.enable('CHIAVE'),
        throwsA(
          isA<WebPushException>().having((e) => e.code, 'code', 'NEGATE'),
        ),
      );
    },
  );

  test('nessuna iscrizione: current e disable rispondono null', () async {
    final push = BrowserWebPush();
    _prova.esito = _esito('', '');
    expect(await push.current(), isNull);
    expect(await push.disable(), isNull);
  });

  test('gli avvisi del service worker arrivano come messaggi', () async {
    final push = BrowserWebPush();
    final received = <WebPushMessage>[];
    push.messages.listen(received.add);
    _prova.avvisa(
      'notifica',
      'Generale',
      'Luca: stasera alle 21',
      '/chat/generale',
      '{"channel":"generale"}',
    );
    _prova.avvisa('apri', '', '', '/presenze', '{}');
    _prova.avvisa('iscrizione', '', '', '', 'non è JSON');
    _prova.avvisa('altro', '', '', '', '{}');
    await pumpEventQueue();
    expect(
      [for (final m in received) m.kind],
      [
        WebPushMessageKind.notification,
        WebPushMessageKind.open,
        WebPushMessageKind.resubscribed,
      ],
    );
    expect(received[0].title, 'Generale');
    expect(received[0].body, 'Luca: stasera alle 21');
    expect(received[0].route, '/chat/generale');
    expect(received[0].data, {'channel': 'generale'});
    expect(received[1].route, '/presenze');
    expect(received[2].data, isEmpty);
  });

  test(
    'senza lo script (pagina vecchia): le notifiche risultano assenti',
    () async {
      _eval('delete window.milanacNotifiche');
      final push = BrowserWebPush();
      expect(push.permission, WebPushPermission.unsupported);
      expect(await push.current(), isNull);
      expect(await push.disable(), isNull);
      await expectLater(
        push.enable('CHIAVE'),
        throwsA(isA<WebPushException>()),
      );
    },
  );
}
