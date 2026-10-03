/// Configurazione passata in fase di build con `--dart-define`.
///
/// Esempio (progetto MILANAC):
/// flutter run --dart-define-from-file=env/prod.json
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Schema URL usato per tornare nell'app dopo il login social.
  static const authRedirect = 'com.milanacproclub.milanac://login-callback';

  /// Senza chiavi Supabase l'app parte in modalità demo (dati di esempio, nessun login).
  static bool get isDemo => supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;

  static const defaultArrivalTime = '21:30';

  /// Email di contatto del club (informativa privacy e pagine degli store).
  static const contactEmail = String.fromEnvironment('CONTACT_EMAIL');
}
