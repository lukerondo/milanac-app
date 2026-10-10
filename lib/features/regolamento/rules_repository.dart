import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';

/// Un articolo del regolamento (bozza del Direttivo o parte di una versione pubblicata).
class RulesArticle {
  const RulesArticle({
    this.id,
    required this.sortOrder,
    required this.title,
    required this.body,
  });
  final String? id;
  final int sortOrder;
  final String title;
  final String body;

  RulesArticle copyWith({int? sortOrder, String? title, String? body}) =>
      RulesArticle(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        title: title ?? this.title,
        body: body ?? this.body,
      );

  factory RulesArticle.fromMap(Map<String, dynamic> m, {int? order}) =>
      RulesArticle(
        id: m['id'] as String?,
        sortOrder: order ?? (m['sort_order'] as num?)?.toInt() ?? 0,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
      );
}

/// Una versione pubblicata: fotografia degli articoli al momento della pubblicazione.
class RulesVersion {
  const RulesVersion({
    required this.number,
    required this.articles,
    this.publishedAt,
  });
  final int number;
  final List<RulesArticle> articles;
  final DateTime? publishedAt;

  factory RulesVersion.fromMap(Map<String, dynamic> m) {
    final snapshot = m['snapshot'];
    return RulesVersion(
      number: (m['number'] as num).toInt(),
      articles: [
        if (snapshot is List)
          for (final (i, a) in snapshot.indexed)
            if (a is Map)
              RulesArticle.fromMap(Map<String, dynamic>.from(a), order: i),
      ],
      publishedAt: m['published_at'] == null
          ? null
          : DateTime.tryParse(m['published_at'] as String)?.toLocal(),
    );
  }
}

abstract class RulesRepository {
  /// Ultima versione pubblicata (null se non ce n'è ancora una).
  Future<RulesVersion?> latest();

  /// Bozza di lavoro del Direttivo.
  Future<List<RulesArticle>> draft();
  Future<void> saveArticle(RulesArticle article);
  Future<void> deleteArticle(String id);
  Future<void> reorder(List<RulesArticle> ordered);

  /// Pubblica la bozza come nuova versione; tutti dovranno riaccettarla.
  Future<int> publish();

  /// Accetta la versione [version] (deve essere l'ultima).
  Future<void> accept(int version);

  /// Entra nel club quando non c'è ancora nessuna versione pubblicata: il profilo
  /// prende il ruolo richiesto; alla prima versione pubblicata tutti la accettano.
  Future<void> enter();
}

/// "Più tardi" del primo Direttivo: per questa sessione l'app non riporta
/// all'editor del regolamento (il promemoria resta nella Sala Direttivo).
class RulesWriteLater extends Notifier<bool> {
  @override
  bool build() => false;

  void postpone() => state = true;
}

final rulesWriteLaterProvider = NotifierProvider<RulesWriteLater, bool>(
  RulesWriteLater.new,
);

final rulesRepositoryProvider = Provider<RulesRepository>((ref) {
  if (AppConfig.isDemo) return DemoRulesRepository.instance;
  return _SupabaseRulesRepository(ref);
});

final latestRulesProvider = FutureProvider<RulesVersion?>(
  (ref) => ref.watch(rulesRepositoryProvider).latest(),
);

final rulesDraftProvider = FutureProvider<List<RulesArticle>>(
  (ref) => ref.watch(rulesRepositoryProvider).draft(),
);

class _SupabaseRulesRepository implements RulesRepository {
  _SupabaseRulesRepository(this._ref);
  final Ref _ref;

  @override
  Future<RulesVersion?> latest() async {
    final row = await _ref
        .read(supabaseProvider)
        .from('rules_versions')
        .select()
        .order('number', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : RulesVersion.fromMap(row);
  }

  @override
  Future<void> enter() async {
    await _ref.read(supabaseProvider).rpc('enter_club');
  }

  @override
  Future<List<RulesArticle>> draft() async {
    final rows = await _ref
        .read(supabaseProvider)
        .from('rules_articles')
        .select()
        .order('sort_order')
        .order('updated_at');
    return rows.map(RulesArticle.fromMap).toList();
  }

  @override
  Future<void> saveArticle(RulesArticle a) async {
    final client = _ref.read(supabaseProvider);
    await client.from('rules_articles').upsert({
      if (a.id != null) 'id': a.id,
      'sort_order': a.sortOrder,
      'title': a.title.trim(),
      'body': a.body.trim(),
      'updated_by': client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> deleteArticle(String id) async {
    await _ref
        .read(supabaseProvider)
        .from('rules_articles')
        .delete()
        .eq('id', id);
  }

  @override
  Future<void> reorder(List<RulesArticle> ordered) async {
    final client = _ref.read(supabaseProvider);
    for (final (i, a) in ordered.indexed) {
      if (a.id == null || a.sortOrder == i) continue;
      await client
          .from('rules_articles')
          .update({'sort_order': i})
          .eq('id', a.id!);
    }
  }

  @override
  Future<int> publish() async {
    final n = await _ref.read(supabaseProvider).rpc('publish_rules');
    return (n as num).toInt();
  }

  @override
  Future<void> accept(int version) async {
    await _ref
        .read(supabaseProvider)
        .rpc('accept_rules', params: {'p_version': version});
  }
}

/// Regolamento di esempio per la demo e i test (l'organigramma viene dalla vecchia app).
class DemoRulesRepository implements RulesRepository {
  DemoRulesRepository._();
  static final instance = DemoRulesRepository._();

  /// Club senza regolamento pubblicato (primo ingresso del Direttivo).
  DemoRulesRepository.unpublished() {
    _version = 0;
    _draft.clear();
    _published = [];
  }

  int _version = 1;
  int _nextId = 10;
  final _draft = <RulesArticle>[
    const RulesArticle(
      id: 'a1',
      sortOrder: 0,
      title: 'Organigramma',
      body:
          'FONDATORI: Fabio Ruggieri, Giuseppe Ruggieri, Christian Rizzi\n'
          'RESP. COMUNICAZIONI E MARKETING: Giuseppe Ruggieri\n'
          'RESP. TECNICO/TATTICO: Fabio Ruggieri\n'
          'RECLUTATORE: Vincenzo Lauricella\n'
          'RESP. TORNEI E AMICHEVOLI: Martin Farias\n'
          'RESP. SOCIAL: Christian Rizzi',
    ),
    const RulesArticle(
      id: 'a2',
      sortOrder: 1,
      title: 'Art. 1 – Presenze',
      body:
          'Gli allenamenti si tengono ogni sera alle 21:30. La presenza, il ritardo '
          'motivato o l\'assenza vanno segnati nell\'app entro le 18:30: chi non '
          'risponde risulta assente.',
    ),
    const RulesArticle(
      id: 'a3',
      sortOrder: 2,
      title: 'Art. 2 – Comportamento',
      body:
          'Rispetto per compagni, avversari e arbitri, in campo e in chat. '
          'Niente abbandoni a partita in corso: chi lascia la squadra in dieci '
          'risponde al Direttivo.',
    ),
    const RulesArticle(
      id: 'a4',
      sortOrder: 3,
      title: 'Art. 3 – Partite ufficiali',
      body:
          'Prima di ogni partita ufficiale aggiorna il gioco e la console. La '
          'formazione pubblicata dal Direttivo è definitiva: chi parte dalla '
          'panchina resta a disposizione per tutta la serata.',
    ),
  ];
  late List<RulesArticle> _published = List.of(_draft);

  @override
  Future<RulesVersion?> latest() async => _version == 0
      ? null
      : RulesVersion(
          number: _version,
          articles: List.of(_published),
          publishedAt: DateTime(2026, 9, 1),
        );

  @override
  Future<void> enter() async {}

  @override
  Future<List<RulesArticle>> draft() async => List.of(_draft);

  @override
  Future<void> saveArticle(RulesArticle a) async {
    final i = _draft.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      _draft[i] = a;
    } else {
      _draft.add(
        RulesArticle(
          id: 'a${_nextId++}',
          sortOrder: a.sortOrder,
          title: a.title,
          body: a.body,
        ),
      );
    }
  }

  @override
  Future<void> deleteArticle(String id) async =>
      _draft.removeWhere((a) => a.id == id);

  @override
  Future<void> reorder(List<RulesArticle> ordered) async {
    _draft
      ..clear()
      ..addAll([
        for (final (i, a) in ordered.indexed) a.copyWith(sortOrder: i),
      ]);
  }

  @override
  Future<int> publish() async {
    _published = List.of(_draft);
    return ++_version;
  }

  @override
  Future<void> accept(int version) async {}
}
