import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import '../auth/gate_ui.dart';
import 'pages_repository.dart';
import 'rules_editor_page.dart';
import 'rules_reader.dart';
import 'rules_repository.dart';

/// Regolamento e Storia (scheda Club): selettore in alto e lettura su fondo scuro.
/// Il Direttivo modifica l'uno o l'altra dalla matita accanto al selettore.
class RegolamentoPage extends ConsumerStatefulWidget {
  const RegolamentoPage({super.key});

  @override
  ConsumerState<RegolamentoPage> createState() => _RegolamentoPageState();
}

class _RegolamentoPageState extends ConsumerState<RegolamentoPage> {
  /// 0 = Regolamento, 1 = Storia.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Le versioni non arrivano in tempo reale: aprendo la sezione si rilegge l'ultima
    // (se è nuova, il router chiede di accettarla).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(latestRulesProvider);
    });
  }

  Future<void> _editRules() async {
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const RulesEditorPage()));
    if (mounted) ref.invalidate(latestRulesProvider);
  }

  Future<void> _editStory() async {
    final current = ref.read(pageContentProvider(ClubPage.storia)).value;
    if (current == null) return;
    final result = await Navigator.of(context, rootNavigator: true)
        .push<String>(
          MaterialPageRoute(builder: (_) => _StoryEditorPage(initial: current)),
        );
    if (result == null || !mounted) return;
    try {
      await ref.read(pagesRepositoryProvider).save(ClubPage.storia, result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
          ),
        );
      }
    }
    if (mounted) ref.invalidate(pageContentProvider(ClubPage.storia));
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final story = _tab == 1;
    return Column(
      children: [
        SubHeader(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SegmentedTabs(
                  labels: const ['Regolamento', 'Storia'],
                  selected: _tab,
                  onSelected: (i) => setState(() => _tab = i),
                ),
              ),
              if (isDirettivo) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: story
                      ? 'Modifica la storia'
                      : 'Modifica il regolamento',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: story ? _editStory : _editRules,
                ),
              ],
            ],
          ),
        ),
        Expanded(child: story ? const _StoryTab() : const _RulesTab()),
      ],
    );
  }
}

class _RulesTab extends ConsumerWidget {
  const _RulesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView<RulesVersion?>(
    value: ref.watch(latestRulesProvider),
    action: 'Impossibile caricare il regolamento',
    onRetry: () => ref.invalidate(latestRulesProvider),
    data: (version) => version == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nessun regolamento pubblicato.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.pal.textMuted, fontSize: 16),
              ),
            ),
          )
        : RulesReader(version: version),
  );
}

class _StoryTab extends ConsumerWidget {
  const _StoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // L'organigramma sta nel regolamento: qui si mostra anche sotto la storia.
    final organigramma = organigrammaOf(ref.watch(latestRulesProvider).value);
    return AsyncView<String>(
      value: ref.watch(pageContentProvider(ClubPage.storia)),
      action: 'Impossibile caricare la storia',
      onRetry: () => ref.invalidate(pageContentProvider(ClubPage.storia)),
      data: (text) => StoryReader(text: text, organigramma: organigramma),
    );
  }
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
      appBar: gateAppBar(
        title: 'MODIFICA LA STORIA',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            style: TextButton.styleFrom(
              foregroundColor: MilanacColors.goldLight,
            ),
            child: const Text('Salva'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Separa i paragrafi con una riga vuota.',
              style: TextStyle(color: context.pal.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
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
    final p = context.pal;
    final children = <Widget>[];
    for (final line in text.split('\n')) {
      if (line.startsWith('## ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: Text(
              line.substring(3),
              style: TextStyle(
                fontFamily: sportFont,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                letterSpacing: .8,
                color: p.accentText,
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
              style: TextStyle(
                fontFamily: sportFont,
                fontWeight: FontWeight.w600,
                fontSize: 22,
                letterSpacing: 1,
                color: p.text,
              ),
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
                Text(
                  '•  ',
                  style: TextStyle(
                    color: p.accentText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Expanded(
                  child: Text(
                    line.substring(2),
                    style: TextStyle(color: p.text, fontSize: 16, height: 1.5),
                  ),
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
            child: Text(
              line,
              style: TextStyle(color: p.text, fontSize: 16, height: 1.5),
            ),
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
