import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import 'pages_repository.dart';
import 'parchment.dart';
import 'rules_editor_page.dart';
import 'rules_reader.dart';
import 'rules_repository.dart';

/// Regolamento e Storia su pergamena, in un'unica sezione a schede.
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
            tabs: [
              Tab(text: 'Regolamento'),
              Tab(text: 'Cenni storici'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RulesTab(editable: isDirettivo),
                _StoryTab(editable: isDirettivo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pergamena tra i due rulli, con lo spazio per il bottone in basso.
class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: Column(
      children: [
        const ParchmentRod(),
        Expanded(child: ParchmentSheet(child: child)),
        const ParchmentRod(),
      ],
    ),
  );
}

class _RulesTab extends ConsumerWidget {
  const _RulesTab({required this.editable});
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(latestRulesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: editable
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () async {
                await Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const RulesEditorPage()),
                );
                ref.invalidate(latestRulesProvider);
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Modifica'),
            )
          : null,
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Retry(
          text: 'Impossibile caricare il regolamento.',
          onRetry: () => ref.invalidate(latestRulesProvider),
        ),
        data: (version) => version == null
            ? const Center(
                child: Text(
                  'Nessun regolamento pubblicato.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            : _Scroll(child: RulesReader(version: version, bottomPadding: 90)),
      ),
    );
  }
}

class _StoryTab extends ConsumerWidget {
  const _StoryTab({required this.editable});
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(pageContentProvider(ClubPage.storia));
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
        error: (e, _) => _Retry(
          text: 'Impossibile caricare la storia.',
          onRetry: () => ref.invalidate(pageContentProvider(ClubPage.storia)),
        ),
        data: (text) => _Scroll(child: StoryReader(text: text)),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final result = await Navigator.of(context, rootNavigator: true)
        .push<String>(
          MaterialPageRoute(builder: (_) => _StoryEditorPage(initial: current)),
        );
    if (result == null) return;
    try {
      await ref.read(pagesRepositoryProvider).save(ClubPage.storia, result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
      }
    }
    ref.invalidate(pageContentProvider(ClubPage.storia));
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.white54),
        const SizedBox(height: 8),
        Text(text),
        TextButton(onPressed: onRetry, child: const Text('Riprova')),
      ],
    ),
  );
}

class _StoryEditorPage extends StatefulWidget {
  const _StoryEditorPage({required this.initial});
  final String initial;

  @override
  State<_StoryEditorPage> createState() => _StoryEditorPageState();
}

class _StoryEditorPageState extends State<_StoryEditorPage> {
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
        title: const Text('MODIFICA STORIA'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text(
              'SALVA',
              style: TextStyle(color: MilanacColors.gold),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Separa i paragrafi con una riga vuota: il primo avrà il capolettera.',
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

/// Formattazione minima: "# " titolo, "## " sottotitolo, "- " elenco puntato
/// (usata dall'informativa privacy).
class SimpleRichText extends StatelessWidget {
  const SimpleRichText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final children = <Widget>[];
    for (final line in text.split('\n')) {
      if (line.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: Text(
              line.substring(3),
              style: theme.titleMedium?.copyWith(
                color: MilanacColors.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      } else if (line.startsWith('# ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.substring(2),
              style: theme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '•  ',
                  style: TextStyle(
                    color: MilanacColors.red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Expanded(
                  child: Text(line.substring(2), style: theme.bodyLarge),
                ),
              ],
            ),
          ),
        );
      } else if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: theme.bodyLarge?.copyWith(height: 1.4)),
          ),
        );
      }
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
