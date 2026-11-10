// La stanza vocale nel browser: il motore Dart contro un `milanacVoce` finto (quello vero
// è web/stanza_vocale.js, sopra l'SDK Web di Agora). Gira solo in un browser:
//   flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/features/voce/voice_engine_web.dart';
import 'package:milanac/features/voce/voice_models.dart';

@JS('eval')
external JSAny? _eval(String code);

@JS('prova')
external _Prova get _prova;

extension type _Prova._(JSObject _) implements JSObject {
  external JSArray<JSString> get chiamate;
  external void parla(JSArray<JSNumber> uids);
  external void caduta(String motivo);
  external void biglietto(bool scaduto);
  external void dentro(String esito);
}

/// Un `milanacVoce` finto: ricorda le chiamate e lascia decidere al test quando (e come)
/// finisce l'ingresso e quando arrivano gli avvisi.
void _fake() => _eval('''
  window.prova = { chiamate: [] };
  window.milanacVoce = {
    entra: function (o) {
      prova.chiamate.push(['entra', o.appId, o.canale, o.token, o.uid, typeof o.uid].join(' '));
      prova.parla = o.parla; prova.caduta = o.caduta; prova.biglietto = o.biglietto;
      var pronto = new Promise(function (ok) { prova.dentro = ok; });
      return {
        pronto: pronto,
        muto: async function (si) { prova.chiamate.push('muto ' + si); },
        rinnova: async function (t) { prova.chiamate.push('rinnova ' + t); },
        esci: async function () { prova.chiamate.push('esci'); prova.dentro('USCITO'); },
      };
    },
  };
''');

List<String> _calls() => [for (final c in _prova.chiamate.toDart) c.toDart];

const _ticket = VoiceTicket(appId: 'APP', token: 'TOK', channel: 'stanza-1');

void main() {
  setUp(_fake);

  test('ingresso, chi parla, muto, rinnovo del biglietto e uscita', () async {
    final engine = createWebVoiceEngine();
    final speaking = <Set<int>>[];
    engine.speaking.listen(speaking.add);
    var asked = 0;
    final joining = engine.join(
      _ticket,
      123456789,
      refreshToken: () async => 'NUOVO-${++asked}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(_calls(), ['entra APP stanza-1 TOK 123456789 number']);
    _prova.dentro('');
    await joining;

    _prova.parla([123456789.toJS, 42.toJS].toJS);
    _prova.parla(<JSNumber>[].toJS);
    await Future<void>.delayed(Duration.zero);
    expect(speaking, [
      {123456789, 42},
      <int>{},
    ]);

    await engine.setMuted(true);
    await engine.setMuted(false);
    await engine.setSpeakerphone(true); // nel browser non fa niente
    // Il biglietto sta per scadere: se ne chiede uno nuovo e lo si passa alla stanza.
    _prova.biglietto(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(asked, 1);
    expect(_calls().sublist(1), ['muto true', 'muto false', 'rinnova NUOVO-1']);

    await engine.dispose();
    await engine.dispose();
    expect(_calls().last, 'esci');
    expect(_calls().where((c) => c == 'esci'), hasLength(1));
  });

  test('ingresso non riuscito: il motivo, in italiano', () async {
    final engine = createWebVoiceEngine();
    final joining = engine.join(_ticket, 7);
    await Future<void>.delayed(Duration.zero);
    _prova.dentro('PERMISSION_DENIED');
    await expectLater(
      joining,
      throwsA(
        isA<VoiceException>().having(
          (e) => e.message,
          'messaggio',
          contains('permesso del microfono'),
        ),
      ),
    );
    await engine.dispose();
  });

  test('uscita durante l\'ingresso: la join si ferma', () async {
    final engine = createWebVoiceEngine();
    final joining = engine.join(_ticket, 7);
    await Future<void>.delayed(Duration.zero);
    unawaited(engine.dispose());
    await expectLater(
      joining,
      throwsA(
        isA<VoiceException>().having(
          (e) => e.message,
          'messaggio',
          'Sei uscito dalla stanza.',
        ),
      ),
    );
  });

  test('chiamata caduta dopo l\'ingresso: arriva il motivo', () async {
    final engine = createWebVoiceEngine();
    final failures = <String>[];
    engine.failures.listen((e) => failures.add(e.message));
    final joining = engine.join(_ticket, 7);
    await Future<void>.delayed(Duration.zero);
    _prova.dentro('');
    await joining;
    _prova.caduta('UID_CONFLICT');
    _prova.caduta('NETWORK_ERROR');
    await Future<void>.delayed(Duration.zero);
    expect(failures, [
      'Sei entrato nella stanza da un altro dispositivo.',
      'Connessione con la stanza persa: controlla la rete e rientra.',
    ]);
    await engine.dispose();
  });

  test('senza lo script della stanza: errore chiaro, non un blocco', () async {
    _eval('delete window.milanacVoce');
    await expectLater(
      createWebVoiceEngine().join(_ticket, 7),
      throwsA(isA<VoiceException>()),
    );
  });
}
