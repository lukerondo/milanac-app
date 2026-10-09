import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/config.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'attendance.dart';
import 'attendance_repository.dart';
import 'evening.dart';

Color statusColor(AttendanceStatus? s, {bool auto = false}) => switch (s) {
  AttendanceStatus.presente => const Color(0xFF2E9E5B),
  AttendanceStatus.ritardo => const Color(0xFFE0A526),
  AttendanceStatus.assente => auto ? Colors.white38 : MilanacColors.red,
  null => Colors.white24,
};

String describeAttendance(AttendanceEntry e) =>
    switch (e.status) {
      AttendanceStatus.presente => 'Presente',
      AttendanceStatus.ritardo => 'In ritardo, arrivo alle ${e.arrivalTime}',
      AttendanceStatus.assente =>
        e.auto ? 'Assente, non ha risposto' : 'Assente',
    } +
    (e.note == null || e.note!.isEmpty ? '' : ' · ${e.note}');

/// Presenze a calendario: oggi in evidenza, per ogni giorno la serata della squadra,
/// la propria risposta (entro le 18:30) e gli elenchi; scheda con le statistiche.
class PresenzePage extends ConsumerStatefulWidget {
  const PresenzePage({super.key, this.initialDay, this.initialTab});

  /// Giorno da aprire (es. dalla notifica di un nuovo evento).
  final DateTime? initialDay;

  /// "calendario" (predefinita) oppure "statistiche".
  final String? initialTab;

  @override
  ConsumerState<PresenzePage> createState() => _PresenzePageState();
}

class _PresenzePageState extends ConsumerState<PresenzePage> {
  late DateTime _day = dayOnly(widget.initialDay ?? ref.read(clockProvider)());
  late DateTime _focused = _day;
  Team? _team;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final rosa = ref.watch(rosaProvider);
    final attendance = ref.watch(attendanceProvider);
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final now = ref.watch(clockProvider)();

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

    final myTeams = me?.teams ?? const {Team.milanac};
    final canPickTeam = myTeams.length > 1 || (me?.isDirettivo ?? false);
    final team = _team ?? mainTeam(myTeams);
    final members =
        rosa.value!
            .where(
              (m) =>
                  m.active &&
                  m.role != ClubRole.pending &&
                  m.teams.contains(team),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final entries = attendance.value!;
    final event = eveningEvent(events, _day, teams: {team});

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab == 'statistiche' ? 1 : 0,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: MilanacColors.red,
            labelColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Calendario'),
              Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Statistiche'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CalendarTab(
                  day: _day,
                  focused: _focused,
                  now: now,
                  me: me,
                  team: team,
                  canPickTeam: canPickTeam,
                  members: members,
                  entries: entries,
                  events: events,
                  event: event,
                  onDay: (d, f) => setState(() {
                    _day = dayOnly(d);
                    _focused = f;
                  }),
                  onTeam: (t) => setState(() => _team = t),
                ),
                _StatsTab(
                  members: members,
                  entries: entries,
                  me: me,
                  now: now,
                  team: team,
                  canPickTeam: canPickTeam,
                  onTeam: (t) => setState(() => _team = t),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ calendario

class _CalendarTab extends ConsumerWidget {
  const _CalendarTab({
    required this.day,
    required this.focused,
    required this.now,
    required this.me,
    required this.team,
    required this.canPickTeam,
    required this.members,
    required this.entries,
    required this.events,
    required this.event,
    required this.onDay,
    required this.onTeam,
  });

  final DateTime day;
  final DateTime focused;
  final DateTime now;
  final Profile? me;
  final Team team;
  final bool canPickTeam;
  final List<Member> members;
  final List<AttendanceEntry> entries;
  final List<ClubEvent> events;
  final ClubEvent event;
  final void Function(DateTime day, DateTime focused) onDay;
  final ValueChanged<Team> onTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dayOnly(now);
    final isToday = day == today;
    final past = day.isBefore(today);
    final open = answersOpen(day, now);
    final ofDay = {
      for (final e in entries.where((e) => e.date == day)) e.playerId: e,
    };
    final mine = me == null ? null : ofDay[me!.id];
    final isMember = me != null && members.any((m) => m.id == me!.id);
    final isDirettivo = me?.isDirettivo ?? false;

    List<ClubEvent> on(DateTime d) => events
        .where(
          (e) =>
              isSameDay(e.startsAt, d) &&
              (e.team == null || e.team == team),
        )
        .toList();
    List<Member> withStatus(AttendanceStatus? s) => members
        .where(
          (m) => s == null ? !ofDay.containsKey(m.id) : ofDay[m.id]?.status == s,
        )
        .toList();

    final dayLabel = DateFormat('EEEE d MMMM', 'it').format(day);

    return ListView(
      key: const ValueKey('presenze-giorno'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
      children: [
        TableCalendar<ClubEvent>(
          locale: 'it',
          firstDay: DateTime(now.year - 1, 1, 1),
          lastDay: DateTime(now.year + 1, 12, 31),
          focusedDay: focused,
          currentDay: today,
          startingDayOfWeek: StartingDayOfWeek.monday,
          // Solo lo scorrimento tra i mesi: in verticale deve scorrere la pagina.
          availableGestures: AvailableGestures.horizontalSwipe,
          availableCalendarFormats: const {CalendarFormat.month: 'Mese'},
          selectedDayPredicate: (d) => isSameDay(d, day),
          eventLoader: on,
          onDaySelected: onDay,
          onPageChanged: (f) => onDay(day, f),
          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextStyle: TextStyle(
              fontFamily: sportFont,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            // Oggi cerchiato in rosso; il giorno scelto pieno.
            todayDecoration: BoxDecoration(
              border: Border.all(color: MilanacColors.red, width: 2),
              shape: BoxShape.circle,
            ),
            todayTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
            selectedDecoration: const BoxDecoration(
              color: MilanacColors.red,
              shape: BoxShape.circle,
            ),
            weekendTextStyle: const TextStyle(color: Colors.white70),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, d, list) => list.isEmpty
                ? null
                : Positioned(
                    bottom: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in list.take(3))
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: e.type.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        if (canPickTeam)
          Center(
            child: SegmentedButton<Team>(
              segments: [
                for (final t in Team.values)
                  ButtonSegment(value: t, label: Text(t.short)),
              ],
              selected: {team},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onTeam(s.first),
            ),
          ),
        // La serata.
        Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: event.type.color.withValues(alpha: .2),
              child: Icon(event.type.icon, color: event.type.color),
            ),
            title: Text(
              '${isToday ? 'STASERA' : 'SERATA'} · ${dayLabel[0].toUpperCase()}${dayLabel.substring(1)}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                fontSize: 13,
              ),
            ),
            subtitle: Text(
              '${event.type.label} alle ${DateFormat('HH:mm').format(event.startsAt)}'
              '${event.title == event.type.label ? '' : ' · ${event.title}'}',
            ),
            trailing: TeamBadge(team, small: true),
          ),
        ),
        if (isMember)
          _MyAnswer(
            mine: mine,
            open: open,
            past: past,
            onAnswer: (s) => answerAttendance(
              context,
              ref,
              playerId: me!.id,
              day: day,
              status: s,
              current: mine,
              event: event,
            ),
          ),
        _Summary(members: members.length, entries: ofDay.values.toList()),
        for (final (title, status) in [
          ('Senza risposta', null),
          ('Presenti', AttendanceStatus.presente),
          ('In ritardo', AttendanceStatus.ritardo),
          ('Assenti', AttendanceStatus.assente),
        ])
          _Group(
            title: title,
            color: statusColor(status),
            members: withStatus(status),
            entries: ofDay,
            me: me,
            history: entries,
            canManage: isDirettivo,
            day: day,
            event: event,
            hideWhenEmpty: status == null,
          ),
      ],
    );
  }
}

/// Riquadro con cui il giocatore risponde per la serata scelta.
class _MyAnswer extends StatelessWidget {
  const _MyAnswer({
    required this.mine,
    required this.open,
    required this.past,
    required this.onAnswer,
  });
  final AttendanceEntry? mine;
  final bool open;
  final bool past;
  final ValueChanged<AttendanceStatus> onAnswer;

  @override
  Widget build(BuildContext context) {
    final text = mine != null
        ? 'La tua risposta: ${describeAttendance(mine!)}'
        : past
        ? 'Non hai risposto.'
        : open
        ? 'Ci sei? Rispondi entro le $attendanceDeadlineLabel.'
        : 'Non hai risposto entro le $attendanceDeadlineLabel: risulti assente.';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LA TUA PRESENZA',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(
                color: mine == null && open
                    ? MilanacColors.gold
                    : Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final s in AttendanceStatus.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AttendanceStatusButton(
                        status: s,
                        selected: mine?.status == s,
                        onPressed: open ? () => onAnswer(s) : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (!open)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  past
                      ? 'Le serate passate non si modificano.'
                      : 'Risposte chiuse alle $attendanceDeadlineLabel. Per un errore, avvisa il Direttivo.',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Risposta (propria, o di un giocatore per mano del Direttivo): chiede orario e nota
/// quando servono, poi salva.
Future<void> answerAttendance(
  BuildContext context,
  WidgetRef ref, {
  required String playerId,
  required DateTime day,
  required AttendanceStatus status,
  AttendanceEntry? current,
  ClubEvent? event,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final input = await editAttendance(
    context,
    status: status,
    initialTime: current?.arrivalTime,
    initialNote: current?.note,
    eventStart: event?.startsAt,
  );
  if (input == null) return;
  try {
    await ref
        .read(attendanceRepositoryProvider)
        .save(
          AttendanceEntry(
            playerId: playerId,
            date: day,
            status: status,
            arrivalTime: input.time,
            note: input.note,
          ),
        );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Risposta non salvata: $e')));
  }
}

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
        side: BorderSide(color: onPressed == null ? Colors.white24 : color),
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

/// Chiede l'orario di arrivo e la nota (obbligatoria) per il ritardo,
/// una nota facoltativa per l'assenza; niente per la presenza.
Future<AttendanceInput?> editAttendance(
  BuildContext context, {
  required AttendanceStatus status,
  String? initialTime,
  String? initialNote,
  DateTime? eventStart,
}) async {
  final start = eventStart == null
      ? AppConfig.defaultArrivalTime
      : DateFormat('HH:mm').format(eventStart);
  if (status == AttendanceStatus.presente) {
    return AttendanceInput(start, null);
  }
  var time = start;
  if (status == AttendanceStatus.ritardo) {
    final base = initialTime == null || initialTime == start
        ? (eventStart ?? DateTime(2000, 1, 1, 21, 30)).add(
            const Duration(minutes: 30),
          )
        : DateTime(
            2000,
            1,
            1,
            int.parse(initialTime.split(':')[0]),
            int.parse(initialTime.split(':')[1]),
          );
    final picked = await showTimePicker(
      context: context,
      helpText: 'A che ora arrivi?',
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
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
      required: status == AttendanceStatus.ritardo,
    ),
  );
  if (note == null) return null;
  return AttendanceInput(time, note.isEmpty ? null : note);
}

/// Dialogo per la nota; restituisce il testo (anche vuoto, se facoltativa) o null se annullato.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.required,
    this.initial,
  });
  final String title;
  final bool required;
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _note.text.trim();
    if (widget.required && text.isEmpty) {
      setState(() => _error = 'Scrivi il motivo del ritardo.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _note,
      autofocus: true,
      maxLength: 200,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: widget.required ? 'Motivo (obbligatorio)' : 'Nota (facoltativa)',
        hintText: widget.required ? 'es. Esco tardi da lavoro' : 'Motivo…',
        errorText: _error,
      ),
      onSubmitted: (_) => _confirm(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('Conferma')),
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

/// Un elenco del giorno (presenti, in ritardo, assenti, senza risposta).
class _Group extends ConsumerWidget {
  const _Group({
    required this.title,
    required this.color,
    required this.members,
    required this.entries,
    required this.me,
    required this.history,
    required this.canManage,
    required this.day,
    required this.event,
    this.hideWhenEmpty = false,
  });
  final String title;
  final Color color;
  final List<Member> members;
  final Map<String, AttendanceEntry> entries;
  final Profile? me;
  final List<AttendanceEntry> history;
  final bool canManage;
  final DateTime day;
  final ClubEvent event;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (members.isEmpty && hideWhenEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text(
            '${title.toUpperCase()} (${members.length})',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        if (members.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('Nessuno.', style: TextStyle(color: Colors.white38)),
          ),
        for (final m in members)
          _MemberTile(
            member: m,
            entry: entries[m.id],
            isMe: m.id == me?.id,
            history: history.where((e) => e.playerId == m.id).toList()
              ..sort((a, b) => b.date.compareTo(a.date)),
            canManage: canManage,
            day: day,
            event: event,
          ),
      ],
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.entry,
    required this.isMe,
    required this.history,
    required this.canManage,
    required this.day,
    required this.event,
  });
  final Member member;
  final AttendanceEntry? entry;
  final bool isMe;
  final List<AttendanceEntry> history;
  final bool canManage;
  final DateTime day;
  final ClubEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final grey = e?.auto ?? false;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: MemberAvatar(member: member, radius: 18),
      title: Text(
        isMe ? '${member.displayName} (tu)' : member.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: grey ? Colors.white54 : null,
        ),
      ),
      subtitle: Text(
        e == null ? 'Non ha ancora risposto' : describeAttendance(e),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: grey ? Colors.white38 : statusColor(e?.status),
          fontSize: 12.5,
        ),
      ),
      trailing: Text(
        '${AttendanceStats(history).percent}%',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: MilanacColors.gold,
        ),
      ),
      onTap: () => showAttendanceHistory(
        context,
        member: member,
        history: history,
        onSetStatus: canManage && !isMe
            ? (s) => answerAttendance(
                context,
                ref,
                playerId: member.id,
                day: day,
                status: s,
                current: e,
                event: event,
              )
            : null,
        dayLabel: DateFormat('d MMMM', 'it').format(day),
      ),
    );
  }
}

// ------------------------------------------------------------------ statistiche

class _StatsTab extends ConsumerWidget {
  const _StatsTab({
    required this.members,
    required this.entries,
    required this.me,
    required this.now,
    required this.team,
    required this.canPickTeam,
    required this.onTeam,
  });
  final List<Member> members;
  final List<AttendanceEntry> entries;
  final Profile? me;
  final DateTime now;
  final Team team;
  final bool canPickTeam;
  final ValueChanged<Team> onTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dayOnly(now);
    final rows = [
      for (final m in members)
        (
          m,
          entries.where((e) => e.playerId == m.id && !e.date.isAfter(today)).toList()
            ..sort((a, b) => b.date.compareTo(a.date)),
        ),
    ]..sort((a, b) {
      final pa = AttendanceStats(a.$2);
      final pb = AttendanceStats(b.$2);
      final c = pb.percent.compareTo(pa.percent);
      return c != 0 ? c : pb.total.compareTo(pa.total);
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Text(
          'Ultimi $historyDays giorni: percentuale di presenze (anche in ritardo), '
          'ritardi e assenze. Le assenze automatiche contano come assenze.',
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (canPickTeam)
          Center(
            child: SegmentedButton<Team>(
              segments: [
                for (final t in Team.values)
                  ButtonSegment(value: t, label: Text(t.short)),
              ],
              selected: {team},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onTeam(s.first),
            ),
          ),
        const SizedBox(height: 8),
        for (final (m, history) in rows)
          _StatsRow(
            member: m,
            history: history,
            isMe: m.id == me?.id,
          ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.member,
    required this.history,
    required this.isMe,
  });
  final Member member;
  final List<AttendanceEntry> history;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final stats = AttendanceStats(history);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            showAttendanceHistory(context, member: member, history: history),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MemberAvatar(member: member, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe ? '${member.displayName} (tu)' : member.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${stats.present} puntuale · ${stats.late} ritardi · '
                          '${stats.absent} assenze'
                          '${stats.autoAbsent > 0 ? ' (${stats.autoAbsent} senza risposta)' : ''}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
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
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _HistoryStrip(history: history.take(12).toList()),
            ],
          ),
        ),
      ),
    );
  }
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
                '${DateFormat('d/M', 'it').format(e.date)} · ${describeAttendance(e)}',
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: statusColor(e.status, auto: e.auto),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// Storico di un giocatore; con [onSetStatus] il Direttivo segna la risposta per lui.
Future<void> showAttendanceHistory(
  BuildContext context, {
  required Member member,
  required List<AttendanceEntry> history,
  Future<void> Function(AttendanceStatus)? onSetStatus,
  String? dayLabel,
}) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _HistorySheet(
    member: member,
    history: history,
    onSetStatus: onSetStatus,
    dayLabel: dayLabel,
  ),
);

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.member,
    required this.history,
    this.onSetStatus,
    this.dayLabel,
  });
  final Member member;
  final List<AttendanceEntry> history;
  final Future<void> Function(AttendanceStatus)? onSetStatus;
  final String? dayLabel;

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
            Text(
              'Segna per questo giocatore${dayLabel == null ? '' : ' · $dayLabel'} (Direttivo):',
            ),
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
                backgroundColor: statusColor(e.status, auto: e.auto),
              ),
              title: Text(DateFormat('EEEE d MMMM yyyy', 'it').format(e.date)),
              subtitle: Text(
                describeAttendance(e),
                style: TextStyle(color: e.auto ? Colors.white38 : null),
              ),
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
