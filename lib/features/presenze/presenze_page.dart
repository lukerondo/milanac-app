import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:table_calendar/table_calendar.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'attendance.dart';
import 'attendance_repository.dart';
import 'attendance_ui.dart';
import 'evening.dart';

export 'attendance_ui.dart' show AttendanceStatusButton;

String describeAttendance(AttendanceEntry e) =>
    switch (e.status) {
      AttendanceStatus.presente => 'Presente',
      AttendanceStatus.ritardo => 'In ritardo, arrivo alle ${e.arrivalTime}',
      AttendanceStatus.assente =>
        e.auto ? 'Assente, non ha risposto' : 'Assente',
    } +
    (e.note == null || e.note!.isEmpty ? '' : ' · ${e.note}');

/// Il dettaglio di una risposta in un elenco che ne dice già lo stato: orario e motivo
/// del ritardo, motivo dell'assenza o "non ha risposto".
String? attendanceDetail(AttendanceEntry e) {
  final note = e.note == null || e.note!.isEmpty ? null : e.note;
  return switch (e.status) {
    AttendanceStatus.presente => note,
    AttendanceStatus.ritardo =>
      'Arrivo alle ${e.arrivalTime}${note == null ? '' : ' · $note'}',
    AttendanceStatus.assente => e.auto ? 'Non ha risposto' : note,
  };
}

String _capitalized(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Presenze: la settimana a colpo d'occhio (o il mese intero), la serata del giorno
/// scelto con la propria risposta (entro le 18:30) e chi c'è; scheda con le statistiche.
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
  late DateTime _day = _dayToOpen(widget.initialDay);

  /// Un giorno della settimana (o del mese) mostrata.
  late DateTime _focused = _day;
  Team? _team;
  late int _tab = _tabOf(widget.initialTab);

  /// Il mese intero al posto della settimana.
  bool _month = false;

  static int _tabOf(String? tab) => tab == 'statistiche' ? 1 : 0;

  /// La pagina aperta senza un giorno chiesto segue oggi: tornando nell'app (per
  /// esempio dalla notifica delle 18:00, dopo una notte con l'app in memoria) e, con
  /// l'app aperta, passata la mezzanotte (controllo ogni minuto).
  AppLifecycleListener? _lifecycle;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _backToToday);
    _midnight = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _backToToday(),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _midnight?.cancel();
    super.dispose();
  }

  void _backToToday() {
    if (!mounted || widget.initialDay != null) return;
    final today = _dayToOpen(null);
    if (_day == today) return;
    setState(() {
      _day = today;
      _focused = today;
    });
  }

  /// Il giorno chiesto dalla rotta (anche uno qualsiasi, da una notifica) dentro i limiti
  /// del calendario; senza richiesta, oggi in Italia.
  DateTime _dayToOpen(DateTime? requested) {
    final today = italianDay(ref.read(clockProvider)());
    return clampToCalendar(requested ?? today, today);
  }

  @override
  void didUpdateWidget(covariant PresenzePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stessa pagina, rotta cambiata (una scelta qui, la notifica di un evento o il
    // promemoria delle 18:00, che riporta a oggi).
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _tab = _tabOf(widget.initialTab));
    }
    if (widget.initialDay != oldWidget.initialDay) {
      setState(() {
        _day = _dayToOpen(widget.initialDay);
        _focused = _day;
      });
    }
  }

  /// Scheda e giorno scelti qui stanno nella rotta, come in Partite: così una notifica
  /// o un collegamento che riporta a `/presenze` cambia sempre la rotta e la pagina lo
  /// segue (con la scelta tenuta solo nella pagina, una rotta uguale non la toccava).
  void _goTo({int? tab, DateTime? day}) {
    final t = tab ?? _tab;
    // Cambiando solo scheda, una pagina che segue oggi continua a seguirlo (il giorno
    // non si fissa nella rotta: dopo la mezzanotte resterebbe "ieri").
    final fixed = day ?? (widget.initialDay == null ? null : _day);
    context.go(
      Uri(
        path: '/presenze',
        queryParameters: {
          if (t == 1) 'scheda': 'statistiche',
          if (fixed != null)
            'giorno': DateFormat('yyyy-MM-dd').format(dayOnly(fixed)),
        },
      ).toString(),
    );
  }

  void _select(DateTime day) => _goTo(day: day);

  /// Avanti o indietro di una settimana (di un mese con il mese intero aperto).
  void _move(int step, DateTime today) {
    final next = _month
        ? DateTime(_focused.year, _focused.month + step, 1)
        : DateTime(_focused.year, _focused.month, _focused.day + 7 * step);
    setState(() => _focused = clampToCalendar(next, today));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final rosa = ref.watch(rosaProvider);
    final attendance = ref.watch(attendanceProvider);
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final now = ref.watch(clockProvider)();
    // Oggi in ora italiana, come sul server.
    final today = italianDay(now);
    // Senza un giorno chiesto la pagina segue oggi: passata la mezzanotte con la pagina
    // aperta si va al giorno nuovo (non resta "ieri", con le risposte già chiuse).
    if (widget.initialDay == null && _day.isBefore(today)) {
      _day = today;
      _focused = today;
    }
    final myTeams = me?.teams ?? const {Team.milanac};
    final canPickTeam = myTeams.length > 1 || (me?.isDirettivo ?? false);
    final team = _team ?? mainTeam(myTeams);
    final teamEvents = [
      for (final e in events)
        if (e.team == null || e.team == team) e,
    ];

    void retry() {
      ref.invalidate(rosaProvider);
      ref.invalidate(attendanceProvider);
    }

    return Column(
      children: [
        _Band(
          tab: _tab,
          onTab: (i) => _goTo(tab: i),
          picker: _tab != 0
              ? null
              : _DayPicker(
                  day: _day,
                  focused: _focused,
                  today: today,
                  month: _month,
                  eventsOn: (d) => [
                    for (final e in teamEvents)
                      if (isSameDay(e.startsAt, d)) e,
                  ],
                  onDay: _select,
                  onFocus: (f) => setState(() => _focused = dayOnly(f)),
                  onMove: (step) => _move(step, today),
                  onToggleMonth: () => setState(() => _month = !_month),
                ),
        ),
        Expanded(
          child: AsyncView(
            value: rosa,
            onRetry: retry,
            data: (all) => AsyncView(
              value: attendance,
              onRetry: retry,
              data: (entries) {
                final members =
                    all
                        .where(
                          (m) =>
                              m.active &&
                              m.role != ClubRole.pending &&
                              m.teams.contains(team),
                        )
                        .toList()
                      ..sort((a, b) => a.displayName.compareTo(b.displayName));
                void onTeam(Team t) => setState(() => _team = t);
                return _tab == 0
                    ? _DayView(
                        day: _day,
                        now: now,
                        me: me,
                        team: team,
                        canPickTeam: canPickTeam,
                        onTeam: onTeam,
                        members: members,
                        entries: entries,
                        event: eveningEvent(events, _day, teams: {team}),
                      )
                    : _StatsView(
                        members: members,
                        entries: entries,
                        me: me,
                        now: now,
                        team: team,
                        canPickTeam: canPickTeam,
                        onTeam: onTeam,
                      );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// La fascia in alto: Calendario | Statistiche e, nel calendario, la settimana.
class _Band extends StatelessWidget {
  const _Band({required this.tab, required this.onTab, this.picker});
  final int tab;
  final ValueChanged<int> onTab;
  final Widget? picker;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            SegmentedTabs(
              labels: const ['Calendario', 'Statistiche'],
              selected: tab,
              onSelected: onTab,
            ),
            if (picker != null) ...[const SizedBox(height: 8), picker!],
          ],
        ),
      ),
    );
  }
}

/// La settimana a colpo d'occhio (oggi in evidenza, pallino oro per le partite e chiaro
/// per gli altri eventi); toccando il mese si apre il mese intero.
class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.day,
    required this.focused,
    required this.today,
    required this.month,
    required this.eventsOn,
    required this.onDay,
    required this.onFocus,
    required this.onMove,
    required this.onToggleMonth,
  });
  final DateTime day;
  final DateTime focused;
  final DateTime today;
  final bool month;
  final List<ClubEvent> Function(DateTime day) eventsOn;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<DateTime> onFocus;
  final ValueChanged<int> onMove;
  final VoidCallback onToggleMonth;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final monday = DateTime(
      focused.year,
      focused.month,
      focused.day - (focused.weekday - 1),
    );
    final week = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final shown = month || !week.contains(day)
        ? (month ? focused : week[3])
        : day;
    final title = DateFormat('MMMM y', 'it').format(shown).toUpperCase();
    final first = calendarFirstDay;
    final last = calendarLastDay(today);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: month ? 'Mese precedente' : 'Settimana precedente',
              icon: const Icon(Icons.chevron_left_rounded),
              color: p.text,
              onPressed: () => onMove(-1),
            ),
            Expanded(
              child: Center(
                child: Semantics(
                  button: true,
                  label: month
                      ? 'Mostra la settimana'
                      : 'Mostra il mese intero',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onToggleMonth,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: sportFont,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 17,
                                    letterSpacing: 1,
                                    color: p.text,
                                  ),
                                ),
                              ),
                            ),
                            Icon(
                              month
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: p.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: month ? 'Mese successivo' : 'Settimana successiva',
              icon: const Icon(Icons.chevron_right_rounded),
              color: p.text,
              onPressed: () => onMove(1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (month)
          _MonthGrid(
            day: day,
            focused: clampToCalendar(focused, today),
            today: today,
            eventsOn: eventsOn,
            onDay: onDay,
            onFocus: onFocus,
          )
        else
          Row(
            children: [
              for (final (i, d) in week.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: _DayTile(
                    day: d,
                    selected: d == day,
                    isToday: d == today,
                    events: eventsOn(d),
                    enabled: !d.isBefore(first) && !d.isAfter(last),
                    onTap: () => onDay(d),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Pallino di un giorno con eventi: oro per le partite, chiaro per il resto.
Color? _dotColor(AppPalette p, List<ClubEvent> events) {
  if (events.isEmpty) return null;
  return events.any((e) => e.type.isMatch) ? p.accentText : p.text;
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.events,
    required this.enabled,
    required this.onTap,
  });
  final DateTime day;
  final bool selected;
  final bool isToday;
  final List<ClubEvent> events;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dot = _dotColor(p, events);
    final number = selected
        ? p.onAccent
        : !enabled
        ? p.textDisabled
        : isToday
        ? p.accentText
        : p.text;
    final weekday = DateFormat('E', 'it').format(day).toUpperCase();
    final label = [
      '${_capitalized(DateFormat('EEEE', 'it').format(day))} ${day.day}',
      if (isToday) 'oggi',
      if (events.any((e) => e.type.isMatch))
        'partita'
      else if (events.isNotEmpty)
        'evento',
    ].join(', ');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.accent : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isToday && !selected
              ? BorderSide(color: p.importantBorder)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? p.onAccent : p.textMuted,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      height: 1.15,
                      color: number,
                    ),
                  ),
                ),
                SizedBox(
                  height: 6,
                  child: dot == null
                      ? null
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected ? p.onAccent : dot,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 6, height: 6),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Il mese intero (stessi colori della settimana).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.day,
    required this.focused,
    required this.today,
    required this.eventsOn,
    required this.onDay,
    required this.onFocus,
  });
  final DateTime day;
  final DateTime focused;
  final DateTime today;
  final List<ClubEvent> Function(DateTime day) eventsOn;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<DateTime> onFocus;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dayStyle = TextStyle(color: p.text, fontWeight: FontWeight.w600);
    final weekdayStyle = TextStyle(
      color: p.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return TableCalendar<ClubEvent>(
      locale: 'it',
      // Gli stessi limiti del Calendario e dell'editor degli eventi.
      firstDay: calendarFirstDay,
      lastDay: calendarLastDay(today),
      focusedDay: focused,
      currentDay: today,
      headerVisible: false,
      rowHeight: 46,
      startingDayOfWeek: StartingDayOfWeek.monday,
      // Solo lo scorrimento tra i mesi: in verticale deve scorrere la pagina.
      availableGestures: AvailableGestures.horizontalSwipe,
      availableCalendarFormats: const {CalendarFormat.month: 'Mese'},
      selectedDayPredicate: (d) => isSameDay(d, day),
      eventLoader: eventsOn,
      onDaySelected: (selected, _) => onDay(selected),
      onPageChanged: onFocus,
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: weekdayStyle,
        weekendStyle: weekdayStyle,
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        defaultTextStyle: dayStyle,
        weekendTextStyle: dayStyle,
        disabledTextStyle: TextStyle(color: p.textDisabled),
        todayDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.accentText, width: 1.5),
        ),
        todayTextStyle: TextStyle(
          color: p.accentText,
          fontWeight: FontWeight.w700,
        ),
        selectedDecoration: BoxDecoration(
          color: p.accent,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(
          color: p.onAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, d, list) {
          final dot = _dotColor(p, list);
          if (dot == null) return null;
          return Positioned(
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isSameDay(d, day) ? p.onAccent : dot,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 5, height: 5),
            ),
          );
        },
      ),
    );
  }
}

/// Scelta della squadra (per chi è in entrambe e per il Direttivo).
class _TeamPills extends StatelessWidget {
  const _TeamPills({required this.team, required this.onTeam});
  final Team team;
  final ValueChanged<Team> onTeam;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in Team.values)
          FilterPill(
            label: teamTabLabel(t),
            selected: t == team,
            onTap: () => onTeam(t),
          ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ la serata

class _DayView extends ConsumerWidget {
  const _DayView({
    required this.day,
    required this.now,
    required this.me,
    required this.team,
    required this.canPickTeam,
    required this.onTeam,
    required this.members,
    required this.entries,
    required this.event,
  });

  final DateTime day;
  final DateTime now;
  final Profile? me;
  final Team team;
  final bool canPickTeam;
  final ValueChanged<Team> onTeam;
  final List<Member> members;
  final List<AttendanceEntry> entries;
  final ClubEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    // Oggi e scadenza in ora italiana, come sul server.
    final today = italianDay(now);
    final open = answersOpen(day, now);
    final ofDay = {
      for (final e in entries.where((e) => e.date == day)) e.playerId: e,
    };
    final me = this.me;
    final mine = me == null ? null : ofDay[me.id];
    final isMember = me != null && members.any((m) => m.id == me.id);
    final isDirettivo = me?.isDirettivo ?? false;

    List<Member> withStatus(AttendanceStatus? s) => members
        .where(
          (m) =>
              s == null ? !ofDay.containsKey(m.id) : ofDay[m.id]?.status == s,
        )
        .toList();

    void openHistory(Member m) {
      // Si prende subito quello che serve per salvare: la riga può cambiare elenco
      // mentre lo storico è aperto (alle 18:30 l'assenza automatica la sposta).
      final answer = AttendanceAnswer(context, ref);
      final entry = ofDay[m.id];
      showAttendanceHistory(
        context,
        member: m,
        // Le risposte già date per i prossimi giorni non gonfiano la percentuale.
        history: historyOf(m.id, entries, today),
        onSetStatus: isDirettivo && m.id != me?.id
            ? (s) => answer(
                playerId: m.id,
                day: day,
                status: s,
                current: entry,
                event: event,
              )
            : null,
        dayLabel: DateFormat('d MMMM', 'it').format(day),
      );
    }

    final groups = [
      ('Presenti', AttendanceStatus.presente),
      ('In ritardo', AttendanceStatus.ritardo),
      ('Senza risposta', null),
      ('Assenti', AttendanceStatus.assente),
    ];

    return ListView(
      key: const ValueKey('presenze-giorno'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (canPickTeam) _TeamPills(team: team, onTeam: onTeam),
        _EveningCard(
          event: event,
          team: team,
          day: day,
          isToday: day == today,
          past: day.isBefore(today),
          open: open,
          isMember: isMember,
          mine: mine,
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
        const SizedBox(height: 16),
        Semantics(
          label: day == today ? 'Chi c\'è stasera' : 'Chi c\'è',
          container: true,
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Nessun giocatore in ${team.label}.',
                      style: TextStyle(color: p.textMuted, fontSize: 15),
                    ),
                  ),
                for (final (title, status) in groups)
                  if (withStatus(status) case final list
                      when list.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 2),
                      child: AttendanceGroupLabel(
                        title: title,
                        count: list.length,
                        status: status,
                      ),
                    ),
                    for (final m in list)
                      AttendanceMemberRow(
                        member: m,
                        isMe: m.id == me?.id,
                        detail: ofDay[m.id] == null
                            ? null
                            : attendanceDetail(ofDay[m.id]!),
                        trailing: memberRoleLabel(m) == null
                            ? null
                            : RowTrailingText(memberRoleLabel(m)!),
                        onTap: () => openHistory(m),
                      ),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// La serata del giorno scelto: l'appuntamento e la propria risposta.
class _EveningCard extends StatelessWidget {
  const _EveningCard({
    required this.event,
    required this.team,
    required this.day,
    required this.isToday,
    required this.past,
    required this.open,
    required this.isMember,
    required this.mine,
    required this.onAnswer,
  });
  final ClubEvent event;
  final Team team;
  final DateTime day;
  final bool isToday;
  final bool past;
  final bool open;
  final bool isMember;
  final AttendanceEntry? mine;
  final ValueChanged<AttendanceStatus> onAnswer;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mine = this.mine;
    final label = isToday
        ? 'Oggi · ${team.label}'
        : '${DateFormat('EEEE d MMMM', 'it').format(day)} · ${team.label}';
    final status = mine != null
        ? 'La tua risposta: ${describeAttendance(mine)}'
        : past
        ? 'Non hai risposto.'
        : open
        ? 'La tua risposta, entro le $attendanceDeadlineLabel'
        : 'Non hai risposto entro le $attendanceDeadlineLabel: risulti assente.';
    final note = past
        ? 'Le serate passate non si modificano.'
        : open
        ? 'Per il ritardo ti chiediamo il motivo. Dopo le '
              '$attendanceDeadlineLabel corregge solo il Direttivo.'
        : 'Risposte chiuse alle $attendanceDeadlineLabel. Per un errore, '
              'avvisa il Direttivo.';
    return AppCard(
      important: isToday,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(label, gold: isToday),
          const SizedBox(height: 2),
          Text(
            '${event.type.label.toUpperCase()} '
            '${DateFormat('HH:mm').format(event.startsAt)}',
            style: TextStyle(
              fontFamily: sportFont,
              fontWeight: FontWeight.w600,
              fontSize: 22,
              letterSpacing: .4,
              color: p.text,
            ),
          ),
          if (event.title != event.type.label)
            Text(
              event.title,
              style: TextStyle(color: p.textSecondary, fontSize: 15),
            ),
          if (isMember) ...[
            const SizedBox(height: 2),
            Text(
              status,
              style: TextStyle(color: p.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 12),
            AttendanceButtons(
              selected: mine?.status,
              inline: true,
              onAnswer: open ? onAnswer : null,
            ),
            const SizedBox(height: 12),
            Text(note, style: TextStyle(color: p.textMuted, fontSize: 14)),
          ],
        ],
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
}) => AttendanceAnswer(context, ref)(
  playerId: playerId,
  day: day,
  status: status,
  current: current,
  event: event,
);

/// Salva le risposte. Repository, avvisi e navigatore si prendono subito, quando nasce:
/// mentre i dialoghi sono aperti la riga che li ha aperti può sparire (alle 18:30
/// l'assenza automatica la sposta in un altro elenco) senza che la risposta si perda.
class AttendanceAnswer {
  AttendanceAnswer(BuildContext context, WidgetRef ref)
    : _repository = ref.read(attendanceRepositoryProvider),
      _myId = ref.read(currentUserIdProvider),
      _messenger = ScaffoldMessenger.of(context),
      _navigator = Navigator.of(context, rootNavigator: true);

  final AttendanceRepository _repository;
  final String? _myId;
  final ScaffoldMessengerState _messenger;
  final NavigatorState _navigator;

  Future<void> call({
    required String playerId,
    required DateTime day,
    required AttendanceStatus status,
    AttendanceEntry? current,
    ClubEvent? event,
  }) async {
    final input = await editAttendance(
      _navigator.context,
      status: status,
      initialTime: current?.arrivalTime,
      initialNote: current?.note,
      eventStart: event?.startsAt,
    );
    if (input == null) return;
    try {
      await _repository.save(
        AttendanceEntry(
          playerId: playerId,
          date: day,
          status: status,
          arrivalTime: input.time,
          note: input.note,
        ),
      );
    } catch (e) {
      _messenger.showSnackBar(
        SnackBar(content: Text(answerErrorText(e, mine: playerId == _myId))),
      );
    }
  }
}

/// Testo per una risposta non salvata. Chi risponde per sé dopo le 18:30 italiane viene
/// fermato dalle regole del database (42501): glielo si dice in chiaro.
String answerErrorText(Object e, {required bool mine}) =>
    mine && e is PostgrestException && e.code == '42501'
    ? 'Le risposte per stasera si sono chiuse alle $attendanceDeadlineLabel '
          '(ora italiana).'
    : friendlyError(e, action: 'Risposta non salvata');

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
        labelText: widget.required
            ? 'Motivo (obbligatorio)'
            : 'Nota (facoltativa)',
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

// ------------------------------------------------------------------ statistiche

class _StatsView extends StatelessWidget {
  const _StatsView({
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
  Widget build(BuildContext context) {
    final today = italianDay(now);
    final rows = [for (final m in members) (m, historyOf(m.id, entries, today))]
      ..sort((a, b) {
        final pa = AttendanceStats(a.$2);
        final pb = AttendanceStats(b.$2);
        final c = pb.percent.compareTo(pa.percent);
        return c != 0 ? c : pb.total.compareTo(pa.total);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (canPickTeam) _TeamPills(team: team, onTeam: onTeam),
        Text(
          'Ultimi $historyDays giorni: percentuale di presenze (anche in ritardo), '
          'ritardi e assenze. Le assenze automatiche contano come assenze.',
          style: TextStyle(color: context.pal.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        for (final (m, history) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StatsRow(member: m, history: history, isMe: m.id == me?.id),
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
    final p = context.pal;
    final stats = AttendanceStats(history);
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.all(12),
      onTap: () =>
          showAttendanceHistory(context, member: member, history: history),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MemberAvatar(member: member, radius: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? '${member.displayName} (tu)' : member.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${stats.present} puntuale · ${stats.late} ritardi · '
                      '${stats.absent} assenze'
                      '${stats.autoAbsent > 0 ? ' (${stats.autoAbsent} senza risposta)' : ''}',
                      style: TextStyle(color: p.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${stats.percent}%',
                style: TextStyle(
                  fontFamily: sportFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  color: p.accentText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HistoryStrip(history: history.take(12).toList()),
        ],
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
    final p = context.pal;
    if (history.isEmpty) {
      return Text(
        'Nessuno storico',
        style: TextStyle(color: p.textMuted, fontSize: 13),
      );
    }
    return Row(
      children: [
        Text('Ultime: ', style: TextStyle(color: p.textMuted, fontSize: 13)),
        for (final e in history)
          Tooltip(
            message:
                '${DateFormat('d/M', 'it').format(e.date)} · ${describeAttendance(e)}',
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: p.status(e.status, auto: e.auto),
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
    final p = context.pal;
    final stats = AttendanceStats(history);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              MemberAvatar(member: member, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName.toUpperCase(),
                      style: TextStyle(
                        fontFamily: sportFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 22,
                        letterSpacing: .4,
                        color: p.text,
                      ),
                    ),
                    Text(
                      'Storico presenze (ultimi $historyDays giorni)',
                      style: TextStyle(color: p.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                _Pill('${stats.percent}%', 'presenze', p.accentText),
                _Pill('${stats.present}', 'puntuale', p.success),
                _Pill('${stats.late}', 'ritardi', p.warning),
                _Pill('${stats.absent}', 'assenze', p.danger),
              ],
            ),
          ),
          if (onSetStatus != null) ...[
            const SizedBox(height: 18),
            Text(
              'Segna per questo giocatore${dayLabel == null ? '' : ' · $dayLabel'} (Direttivo):',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            AttendanceButtons(
              selected: null,
              inline: true,
              onAnswer: (s) async {
                await onSetStatus!(s);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
          const SizedBox(height: 20),
          const SectionLabel('Serate'),
          const SizedBox(height: 4),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nessuna presenza registrata.',
                style: TextStyle(color: p.textMuted, fontSize: 15),
              ),
            ),
          for (final e in history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.status(e.status, auto: e.auto),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _capitalized(
                            DateFormat('EEEE d MMMM yyyy', 'it').format(e.date),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          describeAttendance(e),
                          style: TextStyle(
                            fontSize: 14,
                            color: p.status(e.status, auto: e.auto),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
            fontFamily: sportFont,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            color: color,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(color: context.pal.textMuted, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
