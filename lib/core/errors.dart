import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Errore con il testo già pronto da mostrare all'utente.
class AppError implements Exception {
  const AppError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Il database non ha ancora la funzione (migrazione non applicata): si usa la
/// strada di prima. Codice di PostgREST per "funzione non trovata".
bool isMissingFunction(Object e) =>
    e is PostgrestException && e.code == 'PGRST202';

/// Errore di rete (telefono offline, server irraggiungibile, connessione caduta).
bool isNetworkError(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('clientexception') ||
      s.contains('connection closed') ||
      s.contains('connection reset') ||
      s.contains('network is unreachable') ||
      s.contains('xmlhttprequest error');
}

/// Testo comprensibile per un errore: niente eccezioni grezze sullo schermo.
/// [action] dice cosa non è riuscito ("Salvataggio non riuscito", ...).
String friendlyError(Object e, {String action = 'Operazione non riuscita'}) {
  if (e is AppError) return e.message;
  if (isNetworkError(e)) {
    return 'Nessuna connessione: controlla la rete e riprova.';
  }
  if (e is PostgrestException) {
    // Le regole del database parlano già italiano (raise exception '...').
    if (e.code == 'P0001') return e.message;
    if (e.code == '42501') {
      return '$action: non hai il permesso (o il tempo per farlo è scaduto).';
    }
    if (e.code == '23505') return '$action: esiste già.';
    if (e.code == 'PGRST301' || e.code == 'PGRST303') {
      return 'Sessione scaduta: esci e rientra nell\'app.';
    }
    return '$action: ${e.message}';
  }
  if (e is AuthException) return '$action: ${e.message}';
  if (e is StorageException) return '$action: ${e.message}';
  if (e is FunctionException) {
    return '$action (errore ${e.status}). Riprova.';
  }
  if (e is RealtimeSubscribeException) {
    return 'Aggiornamenti in tempo reale non disponibili: riprova tra poco.';
  }
  return '$action. Riprova.';
}

/// Nuovi tentativi per i dati che arrivano dal server: la rete può mancare per minuti
/// (metro, garage), quindi si riprova senza arrendersi, aspettando sempre di più
/// (0,2 s, 0,4 s, ... fino a 30 s). Gli errori di programmazione non si riprovano.
Duration? retryForever(int retryCount, Object error) {
  if (error is Error) return null;
  final ms = 200 * (1 << retryCount.clamp(0, 8));
  return Duration(milliseconds: ms > 30000 ? 30000 : ms);
}
