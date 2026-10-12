import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Parametri Firebase passati con `--dart-define-from-file=env/prod.json`.
/// Se mancano, le notifiche push sono semplicemente disattivate.
class FirebaseConfig {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _androidKey = String.fromEnvironment('FIREBASE_API_KEY_ANDROID');
  static const _androidApp = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const _iosKey = String.fromEnvironment('FIREBASE_API_KEY_IOS');
  static const _iosApp = String.fromEnvironment('FIREBASE_APP_ID_IOS');

  static FirebaseOptions? get current {
    if (kIsWeb || projectId.isEmpty || senderId.isEmpty) return null;
    final (key, app) = switch (defaultTargetPlatform) {
      TargetPlatform.android => (_androidKey, _androidApp),
      TargetPlatform.iOS => (_iosKey, _iosApp),
      _ => ('', ''),
    };
    if (key.isEmpty || app.isEmpty) return null;
    return FirebaseOptions(
      apiKey: key,
      appId: app,
      messagingSenderId: senderId,
      projectId: projectId,
      iosBundleId: 'com.milanacproclub.milanac',
    );
  }
}

/// Argomento FCM a cui sono iscritti tutti i membri approvati del club.
const clubTopic = 'milanac';

/// Notifiche push tramite Firebase Cloud Messaging (gratuito).
///
/// I messaggi sono inviati per argomento (topic) dai job di GitHub Actions:
/// nuovo Title Update, nuovo evento in calendario, promemoria presenze.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _ready = false;
  bool _subscribed = false;
  void Function(String route)? _onOpenRoute;
  String? _pendingRoute;

  /// Chi apre le sezioni (il router). Se una notifica è arrivata prima che
  /// l'app fosse pronta, la sua rotta viene consegnata appena possibile.
  set onOpenRoute(void Function(String route)? open) {
    _onOpenRoute = open;
    final pending = _pendingRoute;
    if (open != null && pending != null) {
      _pendingRoute = null;
      open(pending);
    }
  }

  /// Con l'app aperta: false per non mostrare l'avviso (es. messaggio del canale già aperto).
  bool Function(Map<String, dynamic> data)? shouldShowInApp;

  StreamSubscription<String>? _tokenRefresh;

  /// Chiamato all'avvio: inizializza Firebase se configurato.
  Future<void> init() async {
    final options = FirebaseConfig.current;
    if (options == null) return;
    try {
      await Firebase.initializeApp(options: options);
      _ready = true;

      // Notifica toccata con l'app in background o chiusa → apri la sezione indicata.
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) scheduleMicrotask(() => _open(initial));

      // Con l'app aperta il sistema non mostra la notifica: la mostriamo noi.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        if (shouldShowInApp != null && !shouldShowInApp!(m.data)) return;
        messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text([n.title, n.body].whereType<String>().join('\n')),
            action: m.data['route'] == null
                ? null
                : SnackBarAction(label: 'Apri', onPressed: () => _open(m)),
          ),
        );
      });
    } catch (e) {
      debugPrint('Notifiche push non disponibili: $e');
    }
  }

  void _open(RemoteMessage m) {
    final route = m.data['route'];
    if (route is! String || !route.startsWith('/')) return;
    final open = _onOpenRoute;
    if (open == null) {
      _pendingRoute = route;
    } else {
      open(route);
    }
  }

  /// Iscrizioni e uscite una alla volta, nell'ordine in cui arrivano (l'uscita di un
  /// account finisce prima che il successivo si iscriva).
  Future<void> _queue = Future.value();

  Future<void> _serial(Future<void> Function() op) =>
      _queue = _queue.then((_) => op()).catchError((Object e) {
        debugPrint('Notifiche: $e');
      });

  /// Senza rete le chiamate a FCM possono restare in sospeso (le iscrizioni ai topic
  /// aspettano la connessione): oltre qualche secondo si va avanti, così un'uscita
  /// dall'account non resta bloccata dietro un'iscrizione.
  static Future<T> _limited<T>(Future<T> call) =>
      call.timeout(const Duration(seconds: 5));

  /// true quando il token di questo telefono è stato cancellato e nessuno si è più
  /// iscritto: un'altra uscita non ha niente da togliere.
  bool _tokenDeleted = false;

  /// Iscrive il dispositivo alle notifiche del club (solo membri approvati).
  /// [onToken] salva il token del telefono per le notifiche personali (formazione, chat).
  /// Risulta iscritto solo a token salvato: se qualcosa non riesce (rete, server) si
  /// riprova alla chiamata successiva.
  Future<void> subscribe({Future<void> Function(String token)? onToken}) {
    if (!_ready) return Future.value();
    return _serial(() async {
      if (_subscribed) return;
      _tokenDeleted = false;
      try {
        final settings = await FirebaseMessaging.instance.requestPermission();
        if (settings.authorizationStatus == AuthorizationStatus.denied) return;
        if (onToken != null) {
          // Prima l'ascolto dei rinnovi, poi il token: un rinnovo nel mezzo non si perde.
          await _tokenRefresh?.cancel();
          _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((
            token,
          ) async {
            try {
              await onToken(token);
            } catch (e) {
              debugPrint('Token delle notifiche non salvato: $e');
            }
          });
          final token = await _limited(FirebaseMessaging.instance.getToken());
          if (token == null) return;
          await _limited(onToken(token));
        }
        await _limited(FirebaseMessaging.instance.subscribeToTopic(clubTopic));
        _subscribed = true;
      } catch (e) {
        debugPrint('Iscrizione alle notifiche non riuscita: $e');
      }
    });
  }

  /// All'uscita dall'account il dispositivo smette di ricevere le notifiche del club e
  /// quelle personali dell'account appena uscito.
  Future<void> unsubscribe({
    Future<void> Function(String token)? onRemoveToken,
  }) {
    if (!_ready) return Future.value();
    return _serial(() async {
      if (_tokenDeleted && !_subscribed) return;
      try {
        await _tokenRefresh?.cancel();
        _tokenRefresh = null;
        final token = await _limited(FirebaseMessaging.instance.getToken());
        if (token != null && onRemoveToken != null) {
          await _limited(onRemoveToken(token));
        }
        await _limited(
          FirebaseMessaging.instance.unsubscribeFromTopic(clubTopic),
        );
      } catch (e) {
        debugPrint('Uscita dalle notifiche non riuscita: $e');
      } finally {
        _subscribed = false;
      }
      // Il token si butta comunque: se la riga non si è potuta cancellare (sessione già
      // scaduta, i permessi lo impediscono) FCM risponde UNREGISTERED e la funzione
      // notify la cancella, così le notifiche personali di chi è uscito non arrivano
      // più qui. Il prossimo account si iscrive con un token nuovo.
      try {
        await _limited(FirebaseMessaging.instance.deleteToken());
        _tokenDeleted = true;
      } catch (e) {
        debugPrint('Token delle notifiche non cancellato: $e');
      }
    });
  }

  bool get isReady => _ready;
}

/// Usato per mostrare messaggi da qualunque punto dell'app.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Avviso in basso sulla pagina aperta, da qualunque punto dell'app (anche fuori dai
/// widget).
void showAppMessage(
  String text, {
  Duration duration = const Duration(seconds: 4),
}) {
  messengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(text), duration: duration),
  );
}
