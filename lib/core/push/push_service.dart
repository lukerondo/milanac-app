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
  void Function(String route)? onOpenRoute;

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
    if (route is String && route.startsWith('/')) onOpenRoute?.call(route);
  }

  /// Iscrive il dispositivo alle notifiche del club (solo membri approvati).
  Future<void> subscribe() async {
    if (!_ready || _subscribed) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      await FirebaseMessaging.instance.subscribeToTopic(clubTopic);
      _subscribed = true;
    } catch (e) {
      debugPrint('Iscrizione alle notifiche non riuscita: $e');
    }
  }

  /// All'uscita dall'account il dispositivo smette di ricevere le notifiche del club.
  Future<void> unsubscribe() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(clubTopic);
      _subscribed = false;
    } catch (_) {}
  }
}

/// Usato per mostrare messaggi da qualunque punto dell'app.
final messengerKey = GlobalKey<ScaffoldMessengerState>();
