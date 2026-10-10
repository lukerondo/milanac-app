import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'rules_repository.dart';

/// Editor del Direttivo: la bozza degli articoli, da pubblicare come nuova versione.
class RulesEditorPage extends ConsumerStatefulWidget {
  const RulesEditorPage({super.key, this.firstTime = false});

  /// Primo ingresso del Direttivo senza regolamento pubblicato: spiega cosa fare,
  /// si può rimandare e, pubblicato, si va alla Home.
  final bool firstTime;

  @override
  ConsumerState<RulesEditorPage> createState() => _RulesEditorPageState();
}

class _RulesEditorPageState extends ConsumerState<RulesEditorPage> {
  bool _publishing = false;

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit([RulesArticle? article, int? count]) async {
    final result = await showDialog<RulesArticle>(
      context: context,
      builder: (_) => _ArticleDialog(article: article, nextOrder: count ?? 0),
    );
    if (result == null) return;
    try {
      await ref.read(rulesRepositoryProvider).saveArticle(result);
      ref.invalidate(rulesDraftProvider);
    } catch (e) {
      _toast('Salvataggio non riuscito: $e');
    }
  }

  Future<void> _delete(RulesArticle a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Eliminare "${a.title}"?'),
        content: const Text('Sparirà dalla prossima versione pubblicata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || a.id == null) return;
    try {
      await ref.read(rulesRepositoryProvider).deleteArticle(a.id!);
      ref.invalidate(rulesDraftProvider);
    } catch (e) {
      _toast('Eliminazione non riuscita: $e');
    }
  }

  Future<void> _reorder(List<RulesArticle> list, int from, int to) async {
    final items = List.of(list);
    final item = items.removeAt(from);
    items.insert(to, item);
    try {
      await ref.read(rulesRepositoryProvider).reorder(items);
      ref.invalidate(rulesDraftProvider);
    } catch (e) {
      _toast('Riordino non riuscito: $e');
    }
  }

  Future<void> _publish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pubblicare la nuova versione?'),
        content: const Text(
          'Tutti i membri riceveranno la notifica e dovranno leggere e accettare '
          'di nuovo il regolamento al prossimo accesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Pubblica'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _publishing = true);
    try {
      final n = await ref.read(rulesRepositoryProvider).publish();
      ref.invalidate(latestRulesProvider);
      _toast('Versione $n pubblicata: tutti dovranno accettarla.');
      if (!mounted) return;
      if (widget.firstTime) {
        context.go('/');
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _toast('Pubblicazione non riuscita: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Widget _body(List<RulesArticle> list) {
    final content = list.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nessun articolo: aggiungi il primo e poi pubblica.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: list.length,
            onReorderItem: (from, to) => _reorder(list, from, to),
            itemBuilder: (context, i) {
              final a = list[i];
              return Card(
                key: ValueKey(a.id ?? i),
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                  title: Text(a.title),
                  subtitle: Text(
                    a.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Azioni',
                    onSelected: (v) =>
                        v == 'edit' ? _edit(a, list.length) : _delete(a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifica')),
                      PopupMenuItem(value: 'delete', child: Text('Elimina')),
                    ],
                  ),
                  onTap: () => _edit(a, list.length),
                ),
              );
            },
          );
    if (!widget.firstTime) return content;
    return Column(
      children: [
        const _FirstTimeIntro(),
        Expanded(child: content),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(rulesDraftProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.firstTime
              ? 'REGOLAMENTO D\'INGRESSO'
              : 'BOZZA DEL REGOLAMENTO',
        ),
        automaticallyImplyLeading: !widget.firstTime,
        actions: [
          if (widget.firstTime)
            TextButton(
              onPressed: () {
                ref.read(rulesWriteLaterProvider.notifier).postpone();
                context.go('/');
              },
              child: const Text(
                'Più tardi',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          TextButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: const Icon(Icons.publish_rounded, color: MilanacColors.gold),
            label: const Text(
              'PUBBLICA',
              style: TextStyle(color: MilanacColors.gold),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MilanacColors.red,
        onPressed: () => _edit(null, draft.value?.length ?? 0),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuovo articolo'),
      ),
      body: draft.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Impossibile caricare la bozza: $e')),
        data: _body,
      ),
    );
  }
}

class _ArticleDialog extends StatefulWidget {
  const _ArticleDialog({required this.article, required this.nextOrder});
  final RulesArticle? article;
  final int nextOrder;

  @override
  State<_ArticleDialog> createState() => _ArticleDialogState();
}

class _ArticleDialogState extends State<_ArticleDialog> {
  late final _title = TextEditingController(text: widget.article?.title);
  late final _body = TextEditingController(text: widget.article?.body);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Servono titolo e testo.')));
      return;
    }
    Navigator.pop(
      context,
      RulesArticle(
        id: widget.article?.id,
        sortOrder: widget.article?.sortOrder ?? widget.nextOrder,
        title: title,
        body: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.article == null ? 'Nuovo articolo' : 'Modifica articolo',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titolo',
              hintText: 'Es. Art. 1 – Presenze',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 5,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Testo',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _save, child: const Text('Salva')),
    ],
  );
}

/// Spiegazione per il primo del Direttivo che entra senza regolamento pubblicato.
class _FirstTimeIntro extends StatelessWidget {
  const _FirstTimeIntro();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: MilanacColors.gold.withValues(alpha: .12),
        border: Border.all(color: MilanacColors.gold.withValues(alpha: .5)),
      ),
      child: const Text(
        'Benvenuto nel Direttivo! Il regolamento d\'ingresso non è ancora stato '
        'scritto e sei tra i primi a entrare: tocca a te. Aggiungi gli articoli '
        'con «Nuovo articolo» e premi PUBBLICA: da quel momento ogni membro '
        'dovrà leggerlo per almeno 2 minuti e accettarlo prima di usare l\'app. '
        'Se adesso non hai tempo, «Più tardi»: il promemoria resta nella Sala '
        'Direttivo.',
        style: TextStyle(color: Colors.white, height: 1.4),
      ),
    ),
  );
}
