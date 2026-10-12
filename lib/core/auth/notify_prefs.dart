import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import 'providers.dart';

/// Notifiche che ognuno può spegnere (Impostazioni → Notifiche). Formazione, risultati,
/// carte speciali e regolamento arrivano sempre: il club deve poterle dire a tutti.
enum NotifyCategory {
  presenze('Presenze e promemoria'),
  chat('Chat e stanze vocali'),
  notizie('Notizie e aggiornamenti');

  const NotifyCategory(this.label);
  final String label;
}

/// Preferenze in `profiles.notify_prefs` ({"presenze": false, ...}): una chiave
/// mancante (o la colonna che manca) vale "attiva".
@immutable
class NotifyPrefs {
  const NotifyPrefs([this.off = const {}]);

  /// Le categorie spente.
  final Set<NotifyCategory> off;

  bool isOn(NotifyCategory c) => !off.contains(c);

  NotifyPrefs set(NotifyCategory c, bool on) =>
      NotifyPrefs(on ? ({...off}..remove(c)) : {...off, c});

  factory NotifyPrefs.fromJson(Object? json) => NotifyPrefs({
    if (json is Map)
      for (final c in NotifyCategory.values)
        if (json[c.name] == false) c,
  });

  Map<String, bool> toJson() => {
    for (final c in NotifyCategory.values) c.name: isOn(c),
  };

  @override
  bool operator ==(Object other) =>
      other is NotifyPrefs && setEquals(other.off, off);

  @override
  int get hashCode => Object.hashAllUnordered(off);
}

abstract class NotifyPrefsRepository {
  /// Salva le preferenze sul proprio profilo (un normale update della propria riga).
  Future<void> save(NotifyPrefs prefs);
}

final notifyPrefsRepositoryProvider = Provider<NotifyPrefsRepository>((ref) {
  if (AppConfig.isDemo) return DemoNotifyPrefsRepository(ref);
  return _SupabaseNotifyPrefsRepository(ref);
});

class _SupabaseNotifyPrefsRepository implements NotifyPrefsRepository {
  _SupabaseNotifyPrefsRepository(this._ref);
  final Ref _ref;

  @override
  Future<void> save(NotifyPrefs prefs) async {
    final client = _ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw const AppError('Sessione scaduta: esci e rientra nell\'app.');
    }
    try {
      await client
          .from('profiles')
          .update({'notify_prefs': prefs.toJson()})
          .eq('id', userId);
    } on PostgrestException catch (e) {
      // Database non ancora aggiornato (colonna mancante: migrazione 0024).
      if (e.code == 'PGRST204') {
        throw const AppError(
          'Le preferenze delle notifiche non sono ancora attive: riprova più tardi.',
        );
      }
      rethrow;
    }
  }
}

/// In demo le preferenze finiscono sul profilo in memoria, come farebbe il tempo reale.
class DemoNotifyPrefsRepository implements NotifyPrefsRepository {
  DemoNotifyPrefsRepository(this._ref);
  final Ref _ref;

  @override
  Future<void> save(NotifyPrefs prefs) async => _ref
      .read(demoProfileProvider.notifier)
      .update((p) => p.withNotifyPrefs(prefs));
}
