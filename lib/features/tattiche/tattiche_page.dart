import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart' show ContentWidth;
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import '../formazione/modules.dart';
import '../lavagna/board_model.dart';
import '../lavagna/board_page.dart';
import '../lavagna/board_painter.dart';
import '../lavagna/full_page.dart';
import 'tactics_repository.dart';

/// Tattiche (nella scheda Club): la lavagna, gli schemi del club con immagine e
/// spiegazione (li pubblica il Direttivo) e, in fondo, le build dei creator, che
/// stanno in Mondo Proclub.
class TattichePage extends ConsumerStatefulWidget {
  const TattichePage({super.key});

  @override
  ConsumerState<TattichePage> createState() => _TattichePageState();
}

class _TattichePageState extends ConsumerState<TattichePage> {
  /// Filtro per modulo o tipo (null = tutti).
  String? _module;

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    return AsyncView(
      value: ref.watch(tacticsProvider),
      onRetry: () => ref.invalidate(tacticsProvider),
      data: (list) {
        // I moduli presenti, nell'ordine degli schemi (i più recenti prima).
        final modules = <String>[];
        for (final t in list) {
          final m = t.module;
          if (m != null && !modules.contains(m)) modules.add(m);
        }
        final module = modules.contains(_module) ? _module : null;
        final shown = [
          for (final t in list)
            if (module == null || t.module == module) t,
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (isDirettivo) ...[
              _ActionCard(
                icon: Icons.draw_rounded,
                title: 'Lavagna',
                subtitle: 'Disegna e registra il replay',
                important: true,
                onTap: () => openBoard(context),
              ),
              const SizedBox(height: 10),
              _ActionCard(
                icon: Icons.add_photo_alternate_rounded,
                title: 'Nuova tattica',
                subtitle: 'Con immagine e spiegazione',
                onTap: () => showTacticEditor(context),
              ),
              const SizedBox(height: 22),
            ],
            const SectionLabel('Schemi del club'),
            const SizedBox(height: 10),
            if (modules.length > 1) ...[
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    FilterPill(
                      label: 'Tutti',
                      selected: module == null,
                      onTap: () => setState(() => _module = null),
                    ),
                    for (final m in modules) ...[
                      const SizedBox(width: 8),
                      FilterPill(
                        label: m,
                        selected: module == m,
                        onTap: () => setState(() => _module = m),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (shown.isEmpty)
              AppCard(
                child: Text(
                  'Nessuno schema ancora.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: context.pal.textMuted),
                ),
              )
            else
              for (final (i, t) in shown.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                _TacticCard(tactic: t),
              ],
            const SizedBox(height: 22),
            const SectionLabel('Build dei creator'),
            const SizedBox(height: 10),
            _ActionCard(
              icon: Icons.smart_display_rounded,
              title: 'Build per ruolo',
              subtitle: 'Video dei creator in Mondo Proclub',
              onTap: () => context.push('/mondo'),
            ),
          ],
        );
      },
    );
  }
}

/// Riga con icona, titolo e descrizione che porta a un'azione (come in Mondo
/// Proclub); [important] = l'azione principale, con il bordo e l'icona d'oro.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.important = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool important;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      important: important,
      radius: 16,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          IconTile(icon, solid: important),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 14, color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
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
      return ColoredBox(color: context.pal.surfaceHigh);
    }
    return Image.network(url, fit: fit);
  }
}

/// Modulo (o tipo) dello schema, e "lavagna" se è disegnato: l'etichetta d'oro
/// sopra il titolo.
String? _category(Tactic t) {
  final parts = [?t.module, if (t.hasBoard) 'lavagna'];
  return parts.isEmpty ? null : parts.join(' · ').toUpperCase();
}

/// Uno schema nell'elenco: la lavagna (o l'immagine) in alto, sotto etichetta,
/// titolo e l'inizio della spiegazione.
class _TacticCard extends StatelessWidget {
  const _TacticCard({required this.tactic});
  final Tactic tactic;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final category = _category(tactic);
    return AppCard(
      padding: EdgeInsets.zero,
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null) ...[
                  Text(
                    category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: p.accentText,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  tactic.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (tactic.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tactic.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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

/// Dettaglio di uno schema: la lavagna (o l'immagine ingrandibile) e la spiegazione.
class TacticPage extends ConsumerWidget {
  const TacticPage({super.key, required this.tacticId});
  final String tacticId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Tactic t) async {
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
            style: dangerButtonStyle(c),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tacticsRepositoryProvider).delete(t);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Eliminazione non riuscita')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final tactics = ref.watch(tacticsProvider);
    final t = tactics.value?.where((x) => x.id == tacticId).firstOrNull;
    final p = context.pal;
    return Scaffold(
      appBar: fullPageBar(
        context,
        title: 'TATTICA',
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
              onPressed: () => _delete(context, ref, t),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: AsyncView(
        value: tactics,
        onRetry: () => ref.invalidate(tacticsProvider),
        data: (_) => t == null
            ? const TacticNotFound()
            : ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    if (t.module != null) ...[
                      SectionLabel(t.module!, gold: true),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      t.title.toUpperCase(),
                      style: TextStyle(
                        fontFamily: sportFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .6,
                        height: 1.2,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (t.hasBoard) ...[
                      BoardPreview(
                        state: t.board!,
                        showNames: true,
                        radius: 16,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => openBoard(
                          context,
                          tactic: t,
                          readOnly: !isDirettivo,
                        ),
                        icon: const Icon(Icons.draw_rounded),
                        label: Text(
                          isDirettivo
                              ? 'Apri la lavagna'
                              : 'Guarda sulla lavagna',
                        ),
                      ),
                    ] else if (t.hasImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: ColoredBox(
                            color: p.surfaceHigh,
                            child: InteractiveViewer(
                              maxScale: 5,
                              child: _TacticImage(t, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                    if (t.description.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const SectionLabel('Spiegazione'),
                      const SizedBox(height: 8),
                      SelectableText(
                        t.description,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          color: p.text,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _image = bytes);
    } catch (e) {
      // Permesso delle foto negato, file illeggibile...
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Immagine non caricata')),
        ),
      );
    }
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
      // Si cambia il testo, non il disegno della lavagna.
      board: widget.tactic?.board,
      team: widget.tactic?.team,
    );
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(tacticsRepositoryProvider).save(t, image: _image);
      // L'elenco si aggiorna anche in tempo reale; per sicurezza si ricarica.
      container.invalidate(tacticsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = [...formationModules.keys, ..._otherModules];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tactic == null ? 'NUOVA TATTICA' : 'MODIFICA TATTICA',
              style: const TextStyle(
                fontFamily: sportFont,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Titolo',
                hintText: 'es. Uscita dal basso con il 3-5-2',
              ),
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 4),
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
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(_image!, height: 160, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Salva tattica'),
            ),
          ],
        ),
      ),
    );
  }
}
