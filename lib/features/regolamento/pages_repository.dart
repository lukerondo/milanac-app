import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';

/// Pagine di testo libero modificabili dal Direttivo (tabella `pages`).
/// Il regolamento non sta qui: vive nelle versioni di `rules_repository.dart`.
enum ClubPage { storia }

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
  Future<void> save(ClubPage page, String content) async {
    final client = _ref.read(supabaseProvider);
    await client.from('pages').upsert({
      'slug': page.name,
      'content': content,
      'updated_by': client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

/// La storia del club com'era nella vecchia app (demo e test).
class DemoPagesRepository implements PagesRepository {
  final _content = <ClubPage, String>{
    ClubPage.storia:
        'Il MilanAc viene fondato a settembre 2025 da Fabio Ruggieri, il quale '
        '(assieme a Giuseppe e Christian) crede fortemente nel progetto di ricreare '
        'le glorie vissute dall\'AC MILAN nel campo reale, anche nel campo virtuale.\n\n'
        'La squadra si forma lentamente ma impreziosendosi sempre di più di elementi '
        'validi, in quanto i fondatori sono convinti che un gruppo solido sia la base '
        'di partenza di fondamentale importanza per ottenere i risultati che i tre si '
        'aspettano.\n\n'
        'I colori sociali del club sono il rosso ed il nero.',
  };

  @override
  Future<String> load(ClubPage page) async => _content[page] ?? '';

  @override
  Future<void> save(ClubPage page, String content) async =>
      _content[page] = content;
}
