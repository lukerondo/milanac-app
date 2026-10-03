import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/shared_links.dart';
import '../formazione/modules.dart';
import '../risultati/match.dart' show youtubeId;
import '../rosa/member.dart';
import 'tactics_repository.dart';

/// Tattiche & Build: video dei creator con le build per ruolo e schemi del club.
class TattichePage extends ConsumerStatefulWidget {
  const TattichePage({super.key});

  @override
  ConsumerState<TattichePage> createState() => _TattichePageState();
}

class _TattichePageState extends ConsumerState<TattichePage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _addBuild() async {
    final link = await showSharedLinkEditor(
      context,
      category: LinkCategory.build,
      tags: fieldPositions,
      titleHint: 'es. La build da ATT più forte',
      noteLabel: 'Creator / note (facoltative)',
    );
    if (link != null) {
      await ref.read(sharedLinksRepositoryProvider).save(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final onBuilds = _tabs.index == 0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: onBuilds
          ? FloatingActionButton.extended(
              heroTag: 'build',
              backgroundColor: MilanacColors.red,
              onPressed: _addBuild,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Aggiungi build'),
            )
          : isDirettivo
          ? FloatingActionButton.extended(
              heroTag: 'tattica',
              backgroundColor: MilanacColors.red,
              onPressed: () => showTacticEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuova tattica'),
            )
          : null,
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            indicatorColor: MilanacColors.red,
            labelColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.smart_display_rounded), text: 'Build'),
              Tab(icon: Icon(Icons.draw_rounded), text: 'Tattiche'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [_BuildsTab(), _TacticsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ build

class _BuildsTab extends ConsumerStatefulWidget {
  const _BuildsTab();

  @override
  ConsumerState<_BuildsTab> createState() => _BuildsTabState();
}

class _BuildsTabState extends ConsumerState<_BuildsTab> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final links = ref.watch(sharedLinksProvider(LinkCategory.build));
    return links.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (all) {
        final roles = {for (final l in all) ?l.tag};
        final shown = all
            .where((l) => _role == null || l.tag == _role)
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const Text(
              'I video dei creator con le build migliori per ogni ruolo. '
              'Chiunque può aggiungerne.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Tutti'),
                  selected: _role == null,
                  onSelected: (_) => setState(() => _role = null),
                ),
                for (final r in fieldPositions.where(roles.contains))
                  ChoiceChip(
                    label: Text(r),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'Nessuna build ancora: aggiungi il primo video!',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            for (final l in shown)
              _BuildCard(
                link: l,
                canEdit: me != null && (me.isDirettivo || l.createdBy == me.id),
              ),
          ],
        );
      },
    );
  }
}

class _BuildCard extends ConsumerWidget {
  const _BuildCard({required this.link, required this.canEdit});
  final SharedLink link;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = youtubeId(link.url);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openSharedLink(link.url),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (id != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      'https://img.youtube.com/vi/$id/hqdefault.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: MilanacColors.surfaceHigh),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: link.tag == null
                  ? null
                  : CircleAvatar(
                      backgroundColor: MilanacColors.red,
                      child: Text(
                        link.tag!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
              title: Text(
                link.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: link.note == null ? null : Text(link.note!),
              trailing: canEdit
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        final repo = ref.read(sharedLinksRepositoryProvider);
                        if (v == 'delete') return repo.delete(link.id);
                        final edited = await showSharedLinkEditor(
                          context,
                          category: LinkCategory.build,
                          link: link,
                          tags: fieldPositions,
                          noteLabel: 'Creator / note (facoltative)',
                        );
                        if (edited != null) await repo.save(edited);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Modifica')),
                        PopupMenuItem(value: 'delete', child: Text('Elimina')),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ tattiche

class _TacticsTab extends ConsumerWidget {
  const _TacticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tactics = ref.watch(tacticsProvider);
    return tactics.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (list) => list.isEmpty
          ? const Center(
              child: Text(
                'Nessuno schema ancora.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [for (final t in list) _TacticCard(tactic: t)],
            ),
    );
  }
}

class _TacticImage extends ConsumerWidget {
  const _TacticImage(this.tactic, {this.fit = BoxFit.cover});
  final Tactic tactic;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tactic.localImage != null) {
      return Image.memory(tactic.localImage!, fit: fit);
    }
    final url = ref.watch(tacticImageUrlProvider(tactic.imagePath!)).value;
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: MilanacColors.surfaceHigh);
    }
    return Image.network(url, fit: fit);
  }
}

class _TacticCard extends StatelessWidget {
  const _TacticCard({required this.tactic});
  final Tactic tactic;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => TacticPage(tacticId: tactic.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tactic.hasImage)
            AspectRatio(aspectRatio: 16 / 9, child: _TacticImage(tactic)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tactic.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (tactic.module != null) _ModuleChip(tactic.module!),
                  ],
                ),
                if (tactic.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    tactic.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ModuleChip extends StatelessWidget {
  const _ModuleChip(this.module);
  final String module;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: MilanacColors.gold),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      module,
      style: const TextStyle(
        color: MilanacColors.gold,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Dettaglio di uno schema: immagine ingrandibile e spiegazione completa.
class TacticPage extends ConsumerWidget {
  const TacticPage({super.key, required this.tacticId});
  final String tacticId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final t = ref
        .watch(tacticsProvider)
        .value
        ?.where((x) => x.id == tacticId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TATTICA'),
        actions: [
          if (isDirettivo && t != null) ...[
            IconButton(
              tooltip: 'Modifica',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => showTacticEditor(context, tactic: t),
            ),
            IconButton(
              tooltip: 'Elimina',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Eliminare la tattica?'),
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
                if (ok != true) return;
                await ref.read(tacticsRepositoryProvider).delete(t);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (t.hasImage)
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: _TacticImage(t, fit: BoxFit.contain),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.module != null) _ModuleChip(t.module!),
                      const SizedBox(height: 8),
                      Text(
                        t.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        t.description,
                        style: const TextStyle(fontSize: 16, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

Future<void> showTacticEditor(BuildContext context, {Tactic? tactic}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TacticEditor(tactic: tactic),
    );

class _TacticEditor extends ConsumerStatefulWidget {
  const _TacticEditor({this.tactic});
  final Tactic? tactic;

  @override
  ConsumerState<_TacticEditor> createState() => _TacticEditorState();
}

class _TacticEditorState extends ConsumerState<_TacticEditor> {
  static const _otherModules = ['Piazzati', 'Difesa', 'Attacco'];
  late final _title = TextEditingController(text: widget.tactic?.title);
  late final _description = TextEditingController(
    text: widget.tactic?.description,
  );
  late String? _module = widget.tactic?.module;
  Uint8List? _image;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _image = bytes);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Inserisci un titolo.')));
      return;
    }
    setState(() => _saving = true);
    final t = Tactic(
      id: widget.tactic?.id ?? '',
      title: _title.text.trim(),
      module: _module,
      description: _description.text.trim(),
      imagePath: widget.tactic?.imagePath,
      localImage: widget.tactic?.localImage,
    );
    try {
      await ref.read(tacticsRepositoryProvider).save(t, image: _image);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = [...formationModules.keys, ..._otherModules];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tactic == null ? 'Nuova tattica' : 'Modifica tattica',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Titolo',
                hintText: 'es. Uscita dal basso con il 3-5-2',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: modules.contains(_module) ? _module : null,
              decoration: const InputDecoration(
                labelText: 'Modulo o tipo (facoltativo)',
              ),
              items: [
                for (final m in modules)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => _module = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              minLines: 4,
              maxLines: 12,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Spiegazione',
                alignLabelWithHint: true,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_rounded),
              label: Text(
                _image != null || (widget.tactic?.hasImage ?? false)
                    ? 'Cambia immagine'
                    : 'Aggiungi immagine (lavagna, screenshot)',
              ),
            ),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_image!, height: 160, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salva tattica'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
