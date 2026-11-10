import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/providers.dart';
import '../config.dart';
import '../local_flags.dart';
import 'push_service.dart';
import 'web_push.dart';

/// Le notifiche in questo browser, come le vede chi usa la web app.
enum BrowserPushStatus {
  /// Il browser non le prevede (o non è un browser: sui telefoni la voce non c'è).
  unsupported,

  /// iPhone e iPad: prima l'app va aggiunta alla schermata Home.
  needsInstall,

  /// Il server non ha ancora le chiavi (funzioni da pubblicare).
  unavailable,

  /// Negate nel browser: si riaprono solo dalle sue impostazioni.
  denied,
  off,
  on,
}

/// Le chiamate al server per le notifiche nel browser (tabella web_push_subscriptions).
abstract class WebPushRepository {
  /// La chiave pubblica del club con cui il browser si iscrive; null se non c'è ancora.
  Future<String?> publicKey();
  Future<void> register(WebPushSubscription subscription);
  Future<void> remove(String endpoint);
}

class _SupabaseWebPushRepository implements WebPushRepository {
  _SupabaseWebPushRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Future<String?> publicKey() async {
    try {
      final key = await _client.rpc('web_push_public_key');
      return key is String && key.isNotEmpty ? key : null;
    } on PostgrestException catch (e) {
      // Database non ancora aggiornato (funzione mancante): come senza chiave.
      if (e.code == 'PGRST202') return null;
      rethrow;
    }
  }

  @override
  Future<void> register(WebPushSubscription s) => _client.rpc(
    'register_web_push',
    params: {'p_endpoint': s.endpoint, 'p_p256dh': s.p256dh, 'p_auth': s.auth},
  );

  @override
  Future<void> remove(String endpoint) =>
      _client.from('web_push_subscriptions').delete().eq('endpoint', endpoint);
}

/// In demo non c'è un server: le notifiche nel browser restano "non disponibili".
class _DemoWebPushRepository implements WebPushRepository {
  @override
  Future<String?> publicKey() async => null;
  @override
  Future<void> register(WebPushSubscription subscription) async {}
  @override
  Future<void> remove(String endpoint) async {}
}

final webPushRepositoryProvider = Provider<WebPushRepository>(
  (ref) => AppConfig.isDemo
      ? _DemoWebPushRepository()
      : _SupabaseWebPushRepository(ref),
);

final browserNotificationsProvider =
    NotifierProvider<BrowserNotifications, BrowserPushStatus>(
      BrowserNotifications.new,
    );

/// Le notifiche della web app in questo browser: iscrizione all'ingresso (se il permesso
/// c'è già), proposta una volta sola a chi non l'ha mai dato, interruttore in
/// Impostazioni → Notifiche, uscita insieme all'account.
class BrowserNotifications extends Notifier<BrowserPushStatus> {
  /// 'si' quando l'utente le ha spente da Impostazioni: non si riaccendono da sole.
  static const offKey = 'notifiche_browser_spente';

  /// Scritto quando la proposta è già stata mostrata in questo browser.
  static const askedKey = 'notifiche_browser_proposte';

  static const proposal =
      'Vuoi ricevere le notifiche del club anche in questo browser?';
  static const enabledMessage = 'Notifiche attive in questo browser.';
  static const deniedMessage =
      'Il browser ha bloccato le notifiche: consentile dal lucchetto accanto '
      'all\'indirizzo della pagina.';
  static const failedMessage =
      'Notifiche non attivate: controlla la connessione e riprova.';
  static const unavailableMessage =
      'Le notifiche nel browser non sono ancora disponibili: riprova più tardi.';

  static const _limit = Duration(seconds: 5);

  String? _publicKey;

  WebPushClient get _client => ref.read(webPushClientProvider);
  WebPushRepository get _repository => ref.read(webPushRepositoryProvider);
  LocalFlags get _flags => ref.read(localFlagsProvider);

  @override
  BrowserPushStatus build() {
    final client = ref.watch(webPushClientProvider);
    final messages = client.messages.listen(_onMessage);
    ref.onDispose(messages.cancel);
    return _resting(client.permission);
  }

  /// Lo stato quando non c'è un'iscrizione attiva.
  BrowserPushStatus _resting(WebPushPermission permission) =>
      switch (permission) {
        WebPushPermission.unsupported => BrowserPushStatus.unsupported,
        WebPushPermission.needsInstall => BrowserPushStatus.needsInstall,
        WebPushPermission.denied => BrowserPushStatus.denied,
        WebPushPermission.ask ||
        WebPushPermission.granted => BrowserPushStatus.off,
      };

  void _onMessage(WebPushMessage m) {
    switch (m.kind) {
      case WebPushMessageKind.notification:
        PushService.instance.showInApp(
          title: m.title,
          body: m.body,
          data: {...m.data, if (m.route.isNotEmpty) 'route': m.route},
        );
      case WebPushMessageKind.open:
        PushService.instance.openRoute(m.route);
      case WebPushMessageKind.resubscribed:
        unawaited(sync());
    }
  }

  /// Ingressi, rinnovi e uscite uno alla volta, nell'ordine in cui arrivano.
  Future<void> _queue = Future.value();

  Future<void> _serial(Future<void> Function() op) =>
      _queue = _queue.then((_) => op()).catchError((Object e) {
        debugPrint('Notifiche nel browser: $e');
      });

  /// Chiamato quando entra un membro approvato: se il permesso c'è già l'iscrizione si
  /// rinnova da sola; a chi non l'ha mai dato si propone, una volta sola.
  Future<void> sync() => _serial(() async {
    if (!ref.mounted) return;
    final permission = _client.permission;
    if (permission == WebPushPermission.unsupported ||
        permission == WebPushPermission.needsInstall) {
      state = _resting(permission);
      return;
    }
    final key = _publicKey ??= await _repository.publicKey().timeout(_limit);
    if (!ref.mounted) return;
    if (key == null) {
      state = BrowserPushStatus.unavailable;
      return;
    }
    if (permission == WebPushPermission.granted &&
        await _flags.getString(offKey) != 'si') {
      try {
        await _repository
            .register(await _client.enable(key).timeout(_limit))
            .timeout(_limit);
        if (ref.mounted) state = BrowserPushStatus.on;
      } catch (e) {
        debugPrint('Iscrizione alle notifiche del browser non riuscita: $e');
        if (ref.mounted) state = BrowserPushStatus.off;
      }
      return;
    }
    state = _resting(permission);
    if (permission == WebPushPermission.ask &&
        await _flags.getString(askedKey) == null) {
      await _flags.setString(askedKey, 'si');
      _propose();
    }
  });

  void _propose() {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text(proposal),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Attiva',
          onPressed: () async =>
              showAppMessage(await turnOn() ?? enabledMessage),
        ),
      ),
    );
  }

  /// Accende le notifiche (dal clic dell'utente: il browser chiede il permesso).
  /// Restituisce il messaggio d'errore, o null se sono attive.
  Future<String?> turnOn() async {
    final key = _publicKey;
    if (key == null) {
      // Chiave non ancora letta (o non ancora sul server): la si rilegge per la prossima.
      unawaited(sync());
      return unavailableMessage;
    }
    // Subito, senza attese prima: il browser mostra la richiesta solo dentro al clic.
    final pending = _client.enable(key);
    try {
      final subscription = await pending;
      await _repository.register(subscription).timeout(_limit);
      await _flags.setString(offKey, 'no');
      if (ref.mounted) state = BrowserPushStatus.on;
      return null;
    } on WebPushException catch (e) {
      debugPrint('Notifiche nel browser non attivate: ${e.code}');
      if (ref.mounted) state = _resting(_client.permission);
      return _client.permission == WebPushPermission.denied
          ? deniedMessage
          : failedMessage;
    } catch (e) {
      debugPrint('Notifiche nel browser non attivate: $e');
      if (ref.mounted) state = _resting(_client.permission);
      return failedMessage;
    }
  }

  /// Spegne le notifiche in questo browser: restano spente finché non si riaccendono.
  Future<void> turnOff() async {
    state = _resting(_client.permission);
    await _flags.setString(offKey, 'si');
    await _serial(_unsubscribe);
  }

  /// All'uscita dall'account: questo browser smette di ricevere le sue notifiche (alla
  /// prossima entrata l'iscrizione si rifà da sola, il permesso resta).
  Future<void> release() => _serial(() async {
    if (_client.permission != WebPushPermission.granted) return;
    await _unsubscribe();
    if (ref.mounted) state = _resting(_client.permission);
  });

  /// Via la riga sul server (finché si è autenticati) e l'iscrizione del browser. Se la
  /// riga non si riesce a togliere (rete, sessione scaduta) il servizio push dirà alla
  /// funzione notify che l'iscrizione non esiste più, e la toglierà lei.
  Future<void> _unsubscribe() async {
    try {
      final current = await _client.current().timeout(_limit);
      if (current != null) {
        await _repository.remove(current.endpoint).timeout(_limit);
      }
    } catch (e) {
      debugPrint('Iscrizione del browser non tolta dal server: $e');
    }
    try {
      await _client.disable().timeout(_limit);
    } catch (e) {
      debugPrint('Iscrizione del browser non tolta: $e');
    }
  }

  /// Il permesso può cambiare dalle impostazioni del browser: all'apertura di
  /// Impostazioni lo stato si riallinea.
  void refresh() {
    final permission = _client.permission;
    final granted = permission == WebPushPermission.granted;
    if (state == BrowserPushStatus.on && !granted) {
      state = _resting(permission);
    } else if (state == BrowserPushStatus.denied && granted) {
      unawaited(sync());
    } else if (state != BrowserPushStatus.on &&
        state != BrowserPushStatus.unavailable) {
      state = _resting(permission);
    }
  }
}
