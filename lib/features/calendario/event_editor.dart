import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'club_event.dart';
import 'events_repository.dart';

Future<void> showEventDetails(
  BuildContext context,
  ClubEvent e, {
  required bool editable,
}) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (sheet) => Consumer(
    builder: (context, ref, _) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(e.type.icon, color: e.type.color),
              const SizedBox(width: 8),
              Text(
                e.type.label.toUpperCase(),
                style: TextStyle(
                  color: e.type.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(e.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            DateFormat(
              "EEEE d MMMM yyyy 'alle' HH:mm",
              'it',
            ).format(e.startsAt),
            style: const TextStyle(color: Colors.white70),
          ),
          if (e.location != null && e.location!.isNotEmpty)
            Row(
              children: [
                const Icon(
                  Icons.place_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  e.location!,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          if (e.description != null && e.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.description!),
          ],
          if (editable) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _confirmDelete(context);
                    if (ok != true) return;
                    await ref.read(eventsRepositoryProvider).delete(e.id);
                    if (sheet.mounted) Navigator.of(sheet).pop();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Elimina'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    showEventEditor(context, event: e);
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Modifica'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  ),
);

Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text("Eliminare l'evento?"),
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

Future<void> showEventEditor(
  BuildContext context, {
  ClubEvent? event,
  DateTime? day,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _EventEditor(event: event, day: day),
);

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({this.event, this.day});
  final ClubEvent? event;
  final DateTime? day;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late EventType _type = widget.event?.type ?? EventType.torneo;
  late final _title = TextEditingController(text: widget.event?.title);
  late final _location = TextEditingController(text: widget.event?.location);
  late final _description = TextEditingController(
    text: widget.event?.description,
  );
  late DateTime _date = widget.event?.startsAt ?? widget.day ?? DateTime.now();
  late TimeOfDay _time = widget.event == null
      ? const TimeOfDay(hour: 21, minute: 30)
      : TimeOfDay.fromDateTime(widget.event!.startsAt);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Inserisci un titolo.')));
      return;
    }
    setState(() => _saving = true);
    final e = ClubEvent(
      id: widget.event?.id ?? '',
      type: _type,
      title: _title.text.trim(),
      startsAt: DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      ),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
    );
    try {
      await ref.read(eventsRepositoryProvider).save(e);
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Salvataggio non riuscito: $err')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              widget.event == null ? 'Nuovo evento' : 'Modifica evento',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in EventType.values)
                  ChoiceChip(
                    avatar: Icon(t.icon, size: 18, color: t.color),
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Titolo',
                hintText: 'es. FVPA – 4ª giornata vs …',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_rounded),
                    title: Text(
                      DateFormat('EEE d MMM yyyy', 'it').format(_date),
                    ),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(DateTime.now().year + 3),
                      );
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(_time.format(context)),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (t != null) setState(() => _time = t);
                    },
                  ),
                ),
              ],
            ),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Luogo / piattaforma (facoltativo)',
                hintText: 'es. PS5, Discord',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (facoltative)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: MilanacColors.red),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salva evento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
