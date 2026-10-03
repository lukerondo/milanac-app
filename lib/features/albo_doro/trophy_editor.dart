import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'albo_doro_page.dart';
import 'scene_painters.dart';
import 'trophies_repository.dart';
import 'trophy.dart';

Future<void> showTrophyDetails(
  BuildContext context,
  Trophy t, {
  required bool canEdit,
}) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (sheet) => Consumer(
    builder: (context, ref, _) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 140, width: 120, child: TrophyVisual(trophy: t)),
          const SizedBox(height: 12),
          Text(
            t.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: MilanacColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            [
              if (t.competition != null) t.competition!,
              if (t.wonOn != null)
                DateFormat('d MMMM yyyy', 'it').format(t.wonOn!),
            ].join(' · '),
            style: const TextStyle(color: Colors.white70),
          ),
          if (t.description != null && t.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t.description!, textAlign: TextAlign.center),
          ],
          if (canEdit) ...[
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Elimina'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Eliminare "${t.name}" dalla bacheca?'),
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
                    await ref.read(trophiesRepositoryProvider).delete(t);
                    ref.invalidate(trophiesProvider(t.seasonId));
                    if (sheet.mounted) Navigator.of(sheet).pop();
                  },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Modifica'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    showTrophyEditor(context, trophy: t);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  ),
);

/// Apre l'editor; restituisce l'id della stagione in cui è stato salvato il trofeo.
Future<String?> showTrophyEditor(
  BuildContext context, {
  Trophy? trophy,
  String? seasonLabel,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _TrophyEditor(trophy: trophy, seasonLabel: seasonLabel),
);

class _TrophyEditor extends ConsumerStatefulWidget {
  const _TrophyEditor({this.trophy, this.seasonLabel});
  final Trophy? trophy;
  final String? seasonLabel;

  @override
  ConsumerState<_TrophyEditor> createState() => _TrophyEditorState();
}

class _TrophyEditorState extends ConsumerState<_TrophyEditor> {
  late final _name = TextEditingController(text: widget.trophy?.name);
  late final _competition = TextEditingController(
    text: widget.trophy?.competition,
  );
  late final _description = TextEditingController(
    text: widget.trophy?.description,
  );
  late final _season = TextEditingController(
    text: widget.seasonLabel ?? currentSeasonLabel(),
  );
  late TrophyShape _shape = widget.trophy?.shape ?? TrophyShape.coppa;
  late DateTime? _wonOn = widget.trophy?.wonOn ?? DateTime.now();
  Uint8List? _image;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.trophy;
    if (t != null) {
      // Stagione del trofeo esistente.
      final season = ref
          .read(seasonsProvider)
          .value
          ?.where((s) => s.id == t.seasonId)
          .firstOrNull;
      if (season != null) _season.text = season.label;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _competition, _description, _season]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _image = bytes);
  }

  Future<void> _save() async {
    final label = _season.text.trim();
    if (_name.text.trim().isEmpty ||
        !RegExp(r'^\d{4}/\d{2}$').hasMatch(label)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci il nome e la stagione nel formato 2025/26.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(trophiesRepositoryProvider);
    try {
      final season = await repo.ensureSeason(label);
      final t = widget.trophy;
      await repo.save(
        Trophy(
          id: t?.id ?? '',
          seasonId: season.id,
          name: _name.text.trim(),
          competition: _competition.text.trim().isEmpty
              ? null
              : _competition.text.trim(),
          wonOn: _wonOn,
          shape: _shape,
          imagePath: t?.imagePath,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        ),
        image: _image,
      );
      ref
        ..invalidate(seasonsProvider)
        ..invalidate(trophiesProvider(season.id));
      if (t != null && t.seasonId != season.id) {
        ref.invalidate(trophiesProvider(t.seasonId));
      }
      if (mounted) Navigator.of(context).pop(season.id);
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
    final hasImage = _image != null || (widget.trophy?.hasImage ?? false);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.trophy == null ? 'Nuovo trofeo' : 'Modifica trofeo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome del trofeo',
                hintText: 'es. Coppa FVPA',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _competition,
                    decoration: const InputDecoration(
                      labelText: 'Competizione (facoltativa)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _season,
                    decoration: const InputDecoration(
                      labelText: 'Stagione',
                      hintText: '2025/26',
                    ),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(
                _wonOn == null
                    ? 'Data della vittoria'
                    : DateFormat('d MMMM yyyy', 'it').format(_wonOn!),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _wonOn ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _wonOn = d);
              },
            ),
            const Text('Forma (usata se non carichi una foto)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in TrophyShape.values)
                  ChoiceChip(
                    avatar: SizedBox(
                      width: 20,
                      height: 20,
                      child: CustomPaint(painter: TrophyShapePainter(s)),
                    ),
                    label: Text(s.label),
                    selected: _shape == s,
                    onSelected: (_) => setState(() => _shape = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: Icon(
                hasImage
                    ? Icons.check_circle_rounded
                    : Icons.add_photo_alternate_rounded,
              ),
              label: Text(
                hasImage
                    ? 'Foto del trofeo caricata (tocca per cambiarla)'
                    : 'Carica foto del trofeo (PNG trasparente consigliato)',
              ),
            ),
            if (_image != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: Image.memory(_image!, fit: BoxFit.contain),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descrizione (facoltativa)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: MilanacColors.red),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Metti in bacheca'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
