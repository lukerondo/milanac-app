import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'web_push.dart';

WebPushClient createWebPushClient() => BrowserWebPush();

/// Le funzioni di `web/notifiche.js` (sopra Web Push e il service worker).
@JS('milanacNotifiche')
external _Notifiche? get _notifiche;

extension type _Notifiche._(JSObject _) implements JSObject {
  external String stato();
  external JSPromise<_Iscrizione> attiva(String pubblica);
  external JSPromise<_Iscrizione> iscrizione();
  external JSPromise<JSString> disattiva();
  external void ascolta(JSFunction avviso);
}

extension type _Iscrizione._(JSObject _) implements JSObject {
  /// '' se è andata bene, altrimenti la sigla dell'errore.
  external String get errore;
  external String get endpoint;
  external String get p256dh;
  external String get auth;
}

/// Le notifiche vere del browser.
class BrowserWebPush implements WebPushClient {
  BrowserWebPush() {
    // Lo script tiene da parte gli avvisi arrivati prima di questo momento.
    _notifiche?.ascolta(_onMessage.toJS);
  }

  final _messages = StreamController<WebPushMessage>.broadcast();

  @override
  Stream<WebPushMessage> get messages => _messages.stream;

  @override
  WebPushPermission get permission => switch (_notifiche?.stato()) {
    'concesse' => WebPushPermission.granted,
    'negate' => WebPushPermission.denied,
    'da_chiedere' => WebPushPermission.ask,
    'da_installare' => WebPushPermission.needsInstall,
    _ => WebPushPermission.unsupported,
  };

  void _onMessage(
    JSString kind,
    JSString title,
    JSString body,
    JSString route,
    JSString data,
  ) {
    final what = switch (kind.toDart) {
      'notifica' => WebPushMessageKind.notification,
      'apri' => WebPushMessageKind.open,
      'iscrizione' => WebPushMessageKind.resubscribed,
      _ => null,
    };
    if (what == null) return;
    Object? decoded;
    try {
      decoded = jsonDecode(data.toDart);
    } catch (_) {}
    _messages.add(
      WebPushMessage(
        what,
        title: title.toDart,
        body: body.toDart,
        route: route.toDart,
        data: decoded is Map<String, dynamic> ? decoded : const {},
      ),
    );
  }

  static WebPushSubscription? _read(_Iscrizione s) {
    if (s.errore.isNotEmpty) throw WebPushException(s.errore);
    if (s.endpoint.isEmpty) return null;
    return WebPushSubscription(
      endpoint: s.endpoint,
      p256dh: s.p256dh,
      auth: s.auth,
    );
  }

  @override
  Future<WebPushSubscription> enable(String publicKey) async {
    final js = _notifiche;
    if (js == null) throw const WebPushException('NON_SUPPORTATE');
    // La chiamata parte subito (dentro al clic); la risposta arriva dopo.
    final pending = js.attiva(publicKey).toDart;
    final sub = _read(await pending);
    if (sub == null) throw const WebPushException('ERRORE');
    return sub;
  }

  @override
  Future<WebPushSubscription?> current() async {
    final js = _notifiche;
    if (js == null) return null;
    return _read(await js.iscrizione().toDart);
  }

  @override
  Future<String?> disable() async {
    final js = _notifiche;
    if (js == null) return null;
    final endpoint = (await js.disattiva().toDart).toDart;
    return endpoint.isEmpty ? null : endpoint;
  }
}
