import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import '../formazione/formazione_page.dart' show formationPath;
import '../presenze/evening.dart';
import 'club_event.dart';
import 'events_repository.dart';

/// Titolo di un foglio (Oswald 22, maiuscolo).
TextStyle _sheetTitle(AppPalette p) => TextStyle(
  fontFamily: sportFont,
  fontWeight: FontWeight.w600,
  fontSize: 22,
  letterSpacing: .5,
  color: p.text,
);

Future<void> showEventDetails(
  BuildContext context,
  ClubEvent e, {
  required bool editable,
}) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => Consumer(
    builder: (context, ref, _) {
      final p = context.pal;
      final when = DateFormat(
        "EEEE d MMMM yyyy 'alle' HH:mm",
        'it',
      ).format(e.startsAt);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(e.type.icon, size: 20, color: p.eventColor(e.type)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        e.type.label,
                        e.team == null ? 'Tutto il club' : e.team!.label,
                      ].join(' · ').toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.eventColor(e.type),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(e.title.toUpperCase(), style: _sheetTitle(p)),
              const SizedBox(height: 4),
              Text(
                '${when[0].toUpperCase()}${when.substring(1)}',
                style: TextStyle(color: p.textSecondary, fontSize: 15),
              ),
              if (e.location != null && e.location!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place_rounded, size: 18, color: p.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.location!,
                        style: TextStyle(color: p.textSecondary, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ],
              if (e.description != null && e.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  e.description!,
                  style: TextStyle(color: p.text, fontSize: 16),
                ),
              ],
              if (e.type == EventType.torneo) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    // La formazione della squadra della partita.
                    context.push(formationPath(e.team));
                  },
                  icon: const Icon(Icons.sports_soccer_rounded),
                  label: const Text('Vedi formazione'),
                ),
              ],
              if (editable) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: p.danger),
                        onPressed: () async {
                          final repository = ref.read(eventsRepositoryProvider);
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await _confirmDelete(context);
                          if (ok != true) return;
                          try {
                            await repository.delete(e.id);
                            if (sheet.mounted) Navigator.of(sheet).pop();
                          } catch (err) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  friendlyError(
                                    err,
                                    action: 'Eliminazione non riuscita',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Elimina'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          showEventEditor(context, event: e);
                        },
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Modifica'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  ),
);

Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text("Eliminare l'evento?"),
    content: const Text('Sparisce dal calendario di tutto il club.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c, false),
        child: const Text('Annulla'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: c.pal.danger,
          foregroundColor: Theme.of(c).colorScheme.onError,
        ),
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
  late Team? _team = widget.event?.team;
  late final _title = TextEditingController(text: widget.event?.title);
  late final _location = TextEditingController(text: widget.event?.location);
  late final _description = TextEditingController(
    text: widget.event?.description,
  );

  /// Oggi in Italia: data e ora dell'evento sono in ora italiana, come lo vedono tutti.
  late final DateTime _today = italianDay(ref.read(clockProvider)());
  late DateTime _date = clampToCalendar(
    widget.event?.startsAt ?? widget.day ?? _today,
    _today,
  );
  late TimeOfDay _time = widget.event == null
      ? const TimeOfDay(hour: 21, minute: 30)
      : TimeOfDay(
          hour: widget.event!.startsAt.hour,
          minute: widget.event!.startsAt.minute,
        );
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
      // Ora italiana (vedi ClubEvent.startsAt).
      startsAt: DateTime.utc(
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
      team: _team,
    );
    try {
      await ref.read(eventsRepositoryProvider).save(e);
      Haptics.confirm();
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(err, action: 'Salvataggio non riuscito'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    // Gli stessi limiti del calendario e delle presenze.
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: calendarFirstDay,
      lastDate: calendarLastDay(_today),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Inizio (ora italiana)',
    );
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
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
              widget.event == null ? 'NUOVO EVENTO' : 'MODIFICA EVENTO',
              style: _sheetTitle(p),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Tipo'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in EventType.values)
                  FilterPill(
                    label: t.label,
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionLabel('Per chi'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterPill(
                  label: 'Tutto il club',
                  selected: _team == null,
                  onTap: () => setState(() => _team = null),
                ),
                for (final t in Team.values)
                  FilterPill(
                    label: teamTabLabel(t),
                    selected: _team == t,
                    onTap: () => setState(() => _team = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Titolo',
                hintText: 'es. FVPA – 4ª giornata vs …',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: Icons.event_rounded,
                    label: 'Giorno',
                    // L'anno solo se non è quello in corso: il campo è stretto.
                    value: DateFormat(
                      _date.year == _today.year ? 'EEE d MMM' : 'd MMM yyyy',
                      'it',
                    ).format(_date),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickerTile(
                    icon: Icons.schedule_rounded,
                    label: 'Ora italiana',
                    value: _time.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Luogo / piattaforma (facoltativo)',
                hintText: 'es. PS5, Discord',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (facoltative)',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Salva evento'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo che apre una scelta (giorno, ora): come i campi di testo del tema.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.borderStrong, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: p.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
