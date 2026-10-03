import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';

/// Pagine di testo modificabili dal Direttivo (tabella `pages`).
enum ClubPage { regolamento, storia }

abstract class PagesRepository {
  Future<String> load(ClubPage page);
  Future<void> save(ClubPage page, String content);
}

final pagesRepositoryProvider = Provider<PagesRepository>((ref) {
  if (AppConfig.isDemo) return DemoPagesRepository();
  return _SupabasePagesRepository(ref);
});

final pageContentProvider = FutureProvider.family<String, ClubPage>(
  (ref, page) => ref.watch(pagesRepositoryProvider).load(page),
);

class _SupabasePagesRepository implements PagesRepository {
  _SupabasePagesRepository(this._ref);
  final Ref _ref;

  @override
  Future<String> load(ClubPage page) async {
    final row = await _ref
        .read(supabaseProvider)
        .from('pages')
        .select('content')
        .eq('slug', page.name)
        .maybeSingle();
    return (row?['content'] as String?) ?? '';
  }

  @override
  Future<void> save(ClubPage page, String content) {
    final client = _ref.read(supabaseProvider);
    return client.from('pages').upsert({
      'slug': page.name,
      'content': content,
      'updated_by': client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

class DemoPagesRepository implements PagesRepository {
  final _content = <ClubPage, String>{
    ClubPage.regolamento: '''# Regolamento interno
## Presenze
- Le partite iniziano alle 21:30: segna la presenza entro le 18:00.
- In caso di ritardo indica l'orario di arrivo nella sezione Presenze.
## Comportamento
- Rispetto per compagni, avversari e arbitri.
- Niente abbandoni a partita in corso.
## Aggiornamenti
- Aggiorna il gioco prima di ogni serata ufficiale.''',
    ClubPage.storia: '''# La nostra storia
Il MILANAC Pro Club nasce nel 2025 da un gruppo di amici tifosi rossoneri.
## Milano siamo noi!
Dai primi tornei FVPA alle sfide tra amici, la squadra cresce stagione dopo stagione.''',
  };

  @override
  Future<String> load(ClubPage page) async => _content[page] ?? '';

  @override
  Future<void> save(ClubPage page, String content) async =>
      _content[page] = content;
}
