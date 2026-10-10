import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../formazione/modules.dart';
import '../lavagna/board_model.dart';
import '../lavagna/board_page.dart';
import '../lavagna/board_painter.dart';
import 'tactics_repository.dart';

/// Tattiche: gli schemi del club con immagine e spiegazione (li pubblica il Direttivo).
/// I video dei creator sono in Mondo Proclub.
class TattichePage extends ConsumerWidget {
  const TattichePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'tattica',
                  backgroundColor: MilanacColors.surfaceHigh,
                  foregroundColor: Colors.white,
                  onPressed: () => showTacticEditor(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nuova tattica'),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'lavagna',
                  backgroundColor: MilanacColors.red,
                  onPressed: () => openBoard(context),
                  icon: const Icon(Icons.draw_rounded),
                  label: const Text('Lavagna'),
                ),
              ],
            )
          : null,
      body: const _TacticsTab(),
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
          if (tactic.hasBoard)
            _BoardThumb(tactic.board!)
          else if (tactic.hasImage)
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
                    if (tactic.hasBoard)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.draw_rounded,
                          size: 18,
                          color: MilanacColors.gold,
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

/// Lo schema della lavagna ritagliato in formato 16:9 (la parte centrale del campo).
class _BoardThumb extends StatelessWidget {
  const _BoardThumb(this.board);
  final BoardState board;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 340,
        height: 340 / boardAspect,
        child: CustomPaint(painter: BoardPainter(board, showNames: false)),
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
                if (t.hasBoard)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      children: [
                        BoardPreview(state: t.board!, showNames: true),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () =>
                              openBoard(context, tactic: t, readOnly: !isDirettivo),
                          icon: const Icon(Icons.draw_rounded),
                          label: Text(
                            isDirettivo ? 'Apri la lavagna' : 'Guarda sulla lavagna',
                          ),
                        ),
                      ],
                    ),
                  )
                else if (t.hasImage)
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
