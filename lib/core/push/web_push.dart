import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart';

/// Cosa permette questo browser alle notifiche della web app.
enum WebPushPermission {
  /// Non è un browser, oppure non prevede le notifiche.
  unsupported,

  /// iPhone e iPad: solo dall'app aggiunta alla schermata Home.
  needsInstall,

  /// Mai chiesto: la richiesta del browser esce al primo "attiva".
  ask,

  /// Negate dall'utente (si riaprono solo dalle impostazioni del browser).
  denied,
  granted,
}

/// L'iscrizione di questo browser: l'indirizzo del servizio push e le due chiavi con cui
/// solo lui decifra i messaggi.
@immutable
class WebPushSubscription {
  const WebPushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });
  final String endpoint;
  final String p256dh;
  final String auth;
}

enum WebPushMessageKind {
  /// Notifica arrivata con l'app aperta e davanti: la mostra l'app.
  notification,

  /// Clic su una notifica di sistema: si apre la sezione.
  open,

  /// Il browser ha rinnovato l'iscrizione: va registrata di nuovo.
  resubscribed,
}

@immutable
class WebPushMessage {
  const WebPushMessage(
    this.kind, {
    this.title = '',
    this.body = '',
    this.route = '',
    this.data = const {},
  });
  final WebPushMessageKind kind;
  final String title;
  final String body;
  final String route;
  final Map<String, dynamic> data;
}

/// L'iscrizione non è riuscita: [code] è la sigla del motivo (`NEGATE`, `NON_CONCESSE`,
/// `NON_SUPPORTATE`, oppure il nome dell'errore del browser).
class WebPushException implements Exception {
  const WebPushException(this.code);
  final String code;

  @override
  String toString() => 'WebPushException($code)';
}

/// Le notifiche del browser (Web Push): nel browser parla con `web/notifiche.js`, altrove
/// non esiste. Nei test si sostituisce.
abstract class WebPushClient {
  WebPushPermission get permission;

  /// Chiede il permesso se serve (va chiamata subito dal clic, senza attese prima) e
  /// iscrive questo browser con la chiave pubblica del club.
  Future<WebPushSubscription> enable(String publicKey);

  /// L'iscrizione che il browser ha già, senza chiedere niente.
  Future<WebPushSubscription?> current();

  /// Toglie l'iscrizione; restituisce l'indirizzo che aveva.
  Future<String?> disable();

  /// Avvisi dal service worker mentre l'app è aperta.
  Stream<WebPushMessage> get messages;
}

/// Fuori dal browser (telefoni, Mac, test): le notifiche arrivano per altre strade.
class NoWebPush implements WebPushClient {
  const NoWebPush();

  @override
  WebPushPermission get permission => WebPushPermission.unsupported;
  @override
  Future<WebPushSubscription> enable(String publicKey) =>
      throw const WebPushException('NON_SUPPORTATE');
  @override
  Future<WebPushSubscription?> current() async => null;
  @override
  Future<String?> disable() async => null;
  @override
  Stream<WebPushMessage> get messages => const Stream.empty();
}

final webPushClientProvider = Provider<WebPushClient>(
  (ref) => kIsWeb ? createWebPushClient() : const NoWebPush(),
);
