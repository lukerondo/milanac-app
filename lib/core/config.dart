/// Configurazione passata in fase di build con `--dart-define`.
///
/// Esempio:
/// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///             --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Schema URL usato per tornare nell'app dopo il login social.
  static const authRedirect = 'com.milanacproclub.milanac://login-callback';

  /// Senza chiavi Supabase l'app parte in modalità demo (dati di esempio, nessun login).
  static bool get isDemo => supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;

  static const defaultArrivalTime = '21:30';
}
