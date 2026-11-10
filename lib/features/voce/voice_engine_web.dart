import 'dart:async';
import 'dart:js_interop';

import 'voice_engine.dart';
import 'voice_models.dart';

VoiceEngine createWebVoiceEngine() => WebVoiceEngine();

/// Le funzioni di `web/stanza_vocale.js` (sopra l'SDK Web di Agora).
@JS('milanacVoce')
external _Voce? get _voce;

extension type _Voce._(JSObject _) implements JSObject {
  external _Sessione entra(_Opzioni opzioni);
}

extension type _Opzioni._(JSObject _) implements JSObject {
  external factory _Opzioni({
    String appId,
    String canale,
    String token,
    int uid,
    JSFunction parla,
    JSFunction caduta,
    JSFunction biglietto,
  });
}

extension type _Sessione._(JSObject _) implements JSObject {
  /// '' quando si è dentro, altrimenti la sigla dell'errore.
  external JSPromise<JSString> get pronto;
  external JSPromise<JSAny?> muto(bool si);
  external JSPromise<JSAny?> rinnova(String token);
  external JSPromise<JSAny?> esci();
}

/// Stanza vera nel browser: la stessa di Agora dei telefoni, con l'SDK Web. Microfono
/// e altoparlante sono quelli scelti dal browser (niente vivavoce da comandare).
class WebVoiceEngine implements VoiceEngine {
  _Sessione? _session;
  final _speaking = StreamController<Set<int>>.broadcast();
  final _failures = StreamController<VoiceException>.broadcast();
  Future<void>? _disposed;
  Future<String> Function()? _refreshToken;
  var _renewing = false;

  @override
  Stream<Set<int>> get speaking => _speaking.stream;

  @override
  Stream<VoiceException> get failures => _failures.stream;

  @override
  Future<void> join(
    VoiceTicket ticket,
    int uid, {
    Future<String> Function()? refreshToken,
  }) async {
    final voce = _voce;
    if (voce == null) {
      throw const VoiceException(
        'La stanza vocale non si è caricata: ricarica la pagina e riprova.',
      );
    }
    _refreshToken = refreshToken;
    final session = _session = voce.entra(
      _Opzioni(
        appId: ticket.appId,
        canale: ticket.channel,
        token: ticket.token,
        uid: uid,
        parla: ((JSArray<JSNumber> uids) {
          if (!_speaking.isClosed) {
            _speaking.add({for (final u in uids.toDart) u.toDartInt});
          }
        }).toJS,
        caduta: ((JSString reason) {
          _fail(VoiceException(voiceWebLostMessage(reason.toDart)));
        }).toJS,
        biglietto: ((JSBoolean expired) {
          // Come sul telefono: 30 secondi prima della scadenza, 10 se è già scaduto.
          unawaited(_renew(Duration(seconds: expired.toDart ? 10 : 30)));
        }).toJS,
      ),
    );
    final String problem;
    try {
      problem = (await session.pronto.toDart.timeout(
        const Duration(seconds: 25),
      )).toDart;
    } on TimeoutException {
      throw const VoiceException(
        'La stanza non risponde: controlla la connessione e riprova.',
      );
    }
    if (_disposed != null) {
      throw const VoiceException('Sei uscito dalla stanza.');
    }
    if (problem.isNotEmpty) throw VoiceException(voiceWebJoinMessage(problem));
  }

  // Il biglietto sta per scadere (o è scaduto): se ne chiede uno nuovo e si rinnova
  // senza uscire, come nell'app. Se non arriva la chiamata finisce con il motivo.
  Future<void> _renew(Duration validFor) async {
    final refresh = _refreshToken;
    final session = _session;
    if (refresh == null || session == null || _renewing) return;
    _renewing = true;
    try {
      final problem = await renewVoiceTicket(
        refresh: refresh,
        apply: (token) async {
          await session.rinnova(token).toDart;
        },
        stopped: () => _disposed != null,
        until: DateTime.now().add(validFor),
      );
      if (problem != null) _fail(problem);
    } finally {
      _renewing = false;
    }
  }

  void _fail(VoiceException e) {
    if (!_failures.isClosed) _failures.add(e);
  }

  @override
  Future<void> setMuted(bool muted) async {
    await _session?.muto(muted).toDart;
  }

  /// Nel browser l'audio esce da dove dice il sistema.
  @override
  Future<void> setSpeakerphone(bool on) async {}

  @override
  Future<void> dispose() => _disposed ??= _release();

  Future<void> _release() async {
    unawaited(_speaking.close());
    unawaited(_failures.close());
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await session.esci().toDart;
    } catch (_) {}
  }
}
