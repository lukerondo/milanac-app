import 'package:flutter/foundation.dart';

/// Configurazione passata in fase di build con `--dart-define`.
///
/// Esempio (progetto MILANAC):
/// flutter run --dart-define-from-file=env/prod.json
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Schema URL usato per tornare nell'app dopo il login social.
  static const authRedirect = 'com.milanacproclub.milanac://login-callback';

  /// Demo chiesta esplicitamente (`--dart-define=DEMO=true`): vale anche in una build
  /// di release per telefono.
  static const demoRequested = bool.fromEnvironment('DEMO');

  static bool get _hasServer =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Senza chiavi Supabase (o se chiesta) l'app parte in modalità demo: dati di esempio,
  /// nessun login. Così partono i test, `flutter run` e la build web per gli screenshot.
  static bool get isDemo => demoRequested || !_hasServer;

  /// Build di release per telefono compilata senza le chiavi (manca
  /// `--dart-define-from-file=env/prod.json`): invece di entrare in demo con i poteri
  /// del Direttivo l'app resta ferma sull'intro con un errore.
  static bool get isMisconfigured =>
      !_hasServer && !demoRequested && kReleaseMode && !kIsWeb;

  static const defaultArrivalTime = '21:30';

  /// Email di contatto del club (informativa privacy e pagine degli store).
  static const contactEmail = String.fromEnvironment('CONTACT_EMAIL');
}
