import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import 'pages_repository.dart';

/// Regolamento e Cenni storici in un'unica sezione a schede.
class RegolamentoPage extends ConsumerWidget {
  const RegolamentoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: MilanacColors.gold,
            labelColor: MilanacColors.gold,
            tabs: [Tab(text: 'Regolamento'), Tab(text: 'Cenni storici')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PageView(page: ClubPage.regolamento, editable: isDirettivo),
                _PageView(page: ClubPage.storia, editable: isDirettivo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageView extends ConsumerWidget {
  const _PageView({required this.page, required this.editable});
  final ClubPage page;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(pageContentProvider(page));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: editable && content.hasValue
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () => _edit(context, ref, content.value!),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Modifica'),
            )
          : null,
      body: content.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (text) => text.trim().isEmpty
            ? const Center(
                child: Text('Nessun contenuto ancora.', style: TextStyle(color: Colors.white54)))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                child: SimpleRichText(text),
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, String current) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _EditorPage(page: page, initial: current)),
    );
    if (result == null) return;
    await ref.read(pagesRepositoryProvider).save(page, result);
    ref.invalidate(pageContentProvider(page));
  }
}

class _EditorPage extends StatefulWidget {
  const _EditorPage({required this.page, required this.initial});
  final ClubPage page;
  final String initial;

  @override
  State<_EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<_EditorPage> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.page == ClubPage.regolamento ? 'MODIFICA REGOLAMENTO' : 'MODIFICA STORIA'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('SALVA', style: TextStyle(color: MilanacColors.gold)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Suggerimento: inizia una riga con "# " per un titolo, "## " per un sottotitolo, "- " per un elenco.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formattazione minima: "# " titolo, "## " sottotitolo, "- " elenco puntato.
class SimpleRichText extends StatelessWidget {
  const SimpleRichText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final children = <Widget>[];
    for (final line in text.split('\n')) {
      if (line.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(line.substring(3),
              style: theme.titleMedium?.copyWith(
                  color: MilanacColors.gold, fontWeight: FontWeight.w800)),
        ));
      } else if (line.startsWith('# ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line.substring(2),
              style: theme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(color: MilanacColors.red, fontWeight: FontWeight.w900)),
              Expanded(child: Text(line.substring(2), style: theme.bodyLarge)),
            ],
          ),
        ));
      } else if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(line, style: theme.bodyLarge?.copyWith(height: 1.4)),
        ));
      }
    }
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
