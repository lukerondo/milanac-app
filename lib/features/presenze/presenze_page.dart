import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'attendance.dart';
import 'attendance_repository.dart';

Color statusColor(AttendanceStatus? s) => switch (s) {
  AttendanceStatus.presente => const Color(0xFF2E9E5B),
  AttendanceStatus.ritardo => const Color(0xFFE0A526),
  AttendanceStatus.assente => MilanacColors.red,
  null => Colors.white24,
};

class PresenzePage extends ConsumerStatefulWidget {
  const PresenzePage({super.key});

  @override
  ConsumerState<PresenzePage> createState() => _PresenzePageState();
}

class _PresenzePageState extends ConsumerState<PresenzePage> {
  DateTime _day = dayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final rosa = ref.watch(rosaProvider);
    final attendance = ref.watch(attendanceProvider);

    if (rosa.isLoading || attendance.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rosa.hasError || attendance.hasError) {
      return Center(
        child: Text(
          'Errore nel caricamento: ${rosa.error ?? attendance.error}',
        ),
      );
    }

    final members =
        rosa.value!
            .where((m) => m.active && m.role != ClubRole.pending)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final entries = attendance.value!;
    final today = {
      for (final e in entries.where((e) => e.date == _day)) e.playerId: e,
    };
    final mine = me == null ? null : today[me.id];
    final isMember = me != null && members.any((m) => m.id == me.id);
    final canEdit = !_day.isBefore(dayOnly(DateTime.now()));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _DaySelector(day: _day, onChanged: (d) => setState(() => _day = d)),
        if (isMember)
          _MyAttendanceCard(
            playerId: me.id,
            day: _day,
            current: mine,
            enabled: canEdit,
          ),
        _Summary(members: members.length, entries: today.values.toList()),
        const SizedBox(height: 8),
        for (final m in members)
          _PlayerRow(
            member: m,
            entry: today[m.id],
            history: entries.where((e) => e.playerId == m.id).toList()
              ..sort((a, b) => b.date.compareTo(a.date)),
            isMe: m.id == me?.id,
            canManage: (me?.isDirettivo ?? false) && canEdit,
            day: _day,
          ),
      ],
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({required this.day, required this.onChanged});
  final DateTime day;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isToday = day == dayOnly(DateTime.now());
    final label = DateFormat('EEEE d MMMM', 'it').format(day);
    return Row(
      children: [
        IconButton(
          tooltip: 'Giorno precedente',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => onChanged(day.subtract(const Duration(days: 1))),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime.now().subtract(
                  const Duration(days: historyDays),
                ),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (picked != null) onChanged(dayOnly(picked));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    isToday ? 'STASERA' : 'SERATA',
                    style: const TextStyle(
                      color: MilanacColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${label[0].toUpperCase()}${label.substring(1)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Giorno successivo',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => onChanged(day.add(const Duration(days: 1))),
        ),
      ],
    );
  }
}

/// Riquadro con cui il giocatore segna la propria presenza.
class _MyAttendanceCard extends ConsumerWidget {
  const _MyAttendanceCard({
    required this.playerId,
    required this.day,
    required this.current,
    required this.enabled,
  });

  final String playerId;
  final DateTime day;
  final AttendanceEntry? current;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LA TUA PRESENZA',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
            const SizedBox(height: 4),
            Text(
              current == null
                  ? 'Inizio previsto alle ${AppConfig.defaultArrivalTime}. Non hai ancora risposto.'
                  : describeAttendance(current!),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final s in AttendanceStatus.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AttendanceStatusButton(
                        status: s,
                        selected: current?.status == s,
                        onPressed: enabled
                            ? () => _answer(context, ref, s)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (!enabled)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Le serate passate non si possono più modificare.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    AttendanceStatus status,
  ) async {
    final result = await editAttendance(
      context,
      status: status,
      initialTime: current?.arrivalTime,
      initialNote: current?.note,
    );
    if (result == null) return;
    await ref
        .read(attendanceRepositoryProvider)
        .save(
          AttendanceEntry(
            playerId: playerId,
            date: day,
            status: status,
            arrivalTime: result.time,
            note: result.note,
          ),
        );
  }
}

String describeAttendance(AttendanceEntry e) =>
    switch (e.status) {
      AttendanceStatus.presente => 'Presente alle ${e.arrivalTime}',
      AttendanceStatus.ritardo => 'In ritardo, arrivo alle ${e.arrivalTime}',
      AttendanceStatus.assente => 'Assente',
    } +
    (e.note == null || e.note!.isEmpty ? '' : ' · ${e.note}');

class AttendanceStatusButton extends StatelessWidget {
  const AttendanceStatusButton({
    super.key,
    required this.status,
    required this.selected,
    this.onPressed,
  });
  final AttendanceStatus status;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final icon = switch (status) {
      AttendanceStatus.presente => Icons.check_circle_rounded,
      AttendanceStatus.ritardo => Icons.schedule_rounded,
      AttendanceStatus.assente => Icons.cancel_rounded,
    };
    return OutlinedButton(
      onPressed: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? color : null,
        foregroundColor: selected ? Colors.white : color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          FittedBox(child: Text(status.label)),
        ],
      ),
    );
  }
}

class AttendanceInput {
  const AttendanceInput(this.time, this.note);
  final String time;
  final String? note;
}

/// Chiede orario di arrivo (solo per il ritardo) e una nota facoltativa.
Future<AttendanceInput?> editAttendance(
  BuildContext context, {
  required AttendanceStatus status,
  String? initialTime,
  String? initialNote,
}) async {
  if (status == AttendanceStatus.presente) {
    return const AttendanceInput(AppConfig.defaultArrivalTime, null);
  }
  var time = initialTime ?? AppConfig.defaultArrivalTime;
  if (status == AttendanceStatus.ritardo) {
    final parts =
        (initialTime == null || initialTime == AppConfig.defaultArrivalTime
                ? '22:00'
                : initialTime)
            .split(':');
    final picked = await showTimePicker(
      context: context,
      helpText: 'A che ora arrivi?',
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return null;
    time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }
  if (!context.mounted) return null;
  final note = await showDialog<String>(
    context: context,
    builder: (_) => _NoteDialog(
      title: status == AttendanceStatus.ritardo
          ? 'Arrivo alle $time'
          : 'Segna assenza',
      initial: initialNote,
    ),
  );
  if (note == null) return null;
  return AttendanceInput(time, note.isEmpty ? null : note);
}

/// Dialogo per la nota facoltativa; restituisce il testo (anche vuoto) o null se annullato.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, this.initial});
  final String title;
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _note,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Nota (facoltativa)',
        hintText: 'Motivo…',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _note.text.trim()),
        child: const Text('Conferma'),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.members, required this.entries});
  final int members;
  final List<AttendanceEntry> entries;

  @override
  Widget build(BuildContext context) {
    int count(AttendanceStatus s) => entries.where((e) => e.status == s).length;
    final waiting = members - entries.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            for (final (label, value, color) in [
              (
                'Presenti',
                count(AttendanceStatus.presente),
                statusColor(AttendanceStatus.presente),
              ),
              (
                'Ritardi',
                count(AttendanceStatus.ritardo),
                statusColor(AttendanceStatus.ritardo),
              ),
              (
                'Assenti',
                count(AttendanceStatus.assente),
                statusColor(AttendanceStatus.assente),
              ),
              ('Senza risposta', waiting < 0 ? 0 : waiting, Colors.white54),
            ])
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    FittedBox(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({
    required this.member,
    required this.entry,
    required this.history,
    required this.isMe,
    required this.canManage,
    required this.day,
  });

  final Member member;
  final AttendanceEntry? entry;
  final List<AttendanceEntry> history;
  final bool isMe;
  final bool canManage;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = AttendanceStats(history);
    final status = entry?.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showHistory(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor(status),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe
                              ? '${member.displayName} (tu)'
                              : member.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          entry == null
                              ? 'Non ha ancora risposto'
                              : describeAttendance(entry!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor(status),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${stats.percent}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: MilanacColors.gold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _HistoryStrip(
                history: history
                    .where((e) => e.date.isBefore(day))
                    .take(10)
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHistory(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _HistorySheet(
          member: member,
          history: history,
          onSetStatus: canManage && !isMe
              ? (s) async {
                  final input = await editAttendance(
                    context,
                    status: s,
                    initialTime: entry?.arrivalTime,
                    initialNote: entry?.note,
                  );
                  if (input == null) return;
                  await ref
                      .read(attendanceRepositoryProvider)
                      .save(
                        AttendanceEntry(
                          playerId: member.id,
                          date: day,
                          status: s,
                          arrivalTime: input.time,
                          note: input.note,
                        ),
                      );
                }
              : null,
        ),
      );
}

/// Pallini colorati delle ultime serate (la più recente a sinistra).
class _HistoryStrip extends StatelessWidget {
  const _HistoryStrip({required this.history});
  final List<AttendanceEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Text(
        'Nessuno storico',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
    }
    return Row(
      children: [
        const Text(
          'Ultime: ',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        for (final e in history)
          Tooltip(
            message:
                '${DateFormat('d/M', 'it').format(e.date)} · ${e.status.label}',
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: statusColor(e.status),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.member,
    required this.history,
    this.onSetStatus,
  });
  final Member member;
  final List<AttendanceEntry> history;
  final Future<void> Function(AttendanceStatus)? onSetStatus;

  @override
  Widget build(BuildContext context) {
    final stats = AttendanceStats(history);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            member.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Storico presenze (ultimi $historyDays giorni)',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Pill('${stats.percent}%', 'presenze', MilanacColors.gold),
              _Pill(
                '${stats.present}',
                'puntuale',
                statusColor(AttendanceStatus.presente),
              ),
              _Pill(
                '${stats.late}',
                'ritardi',
                statusColor(AttendanceStatus.ritardo),
              ),
              _Pill(
                '${stats.absent}',
                'assenze',
                statusColor(AttendanceStatus.assente),
              ),
            ],
          ),
          if (onSetStatus != null) ...[
            const SizedBox(height: 16),
            const Text('Segna per questo giocatore (Direttivo):'),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in AttendanceStatus.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AttendanceStatusButton(
                        status: s,
                        selected: false,
                        onPressed: () async {
                          await onSetStatus!(s);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (history.isEmpty)
            const Text(
              'Nessuna presenza registrata.',
              style: TextStyle(color: Colors.white54),
            ),
          for (final e in history)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 8,
                backgroundColor: statusColor(e.status),
              ),
              title: Text(DateFormat('EEEE d MMMM yyyy', 'it').format(e.date)),
              subtitle: Text(describeAttendance(e)),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        FittedBox(
          child: Text(label, style: const TextStyle(color: Colors.white60)),
        ),
      ],
    ),
  );
}
