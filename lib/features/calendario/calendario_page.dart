import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import 'club_event.dart';
import 'event_editor.dart';
import 'events_repository.dart';

class CalendarioPage extends ConsumerStatefulWidget {
  const CalendarioPage({super.key});

  @override
  ConsumerState<CalendarioPage> createState() => _CalendarioPageState();
}

class _CalendarioPageState extends ConsumerState<CalendarioPage> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final events = ref.watch(eventsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () => showEventEditor(context, day: _selected),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuovo evento'),
            )
          : null,
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore nel caricamento: $e')),
        data: (all) {
          List<ClubEvent> on(DateTime day) =>
              all.where((e) => isSameDay(e.startsAt, day)).toList();
          final dayEvents = on(_selected);
          final now = DateTime.now();
          final upcoming = all
              .where((e) => e.startsAt.isAfter(now))
              .take(5)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              TableCalendar<ClubEvent>(
                locale: 'it',
                firstDay: DateTime(2024),
                lastDay: DateTime(now.year + 3),
                focusedDay: _focused,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableGestures: AvailableGestures.horizontalSwipe,
                availableCalendarFormats: const {CalendarFormat.month: 'Mese'},
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                eventLoader: on,
                onDaySelected: (selected, focused) => setState(() {
                  _selected = selected;
                  _focused = focused;
                }),
                onPageChanged: (f) => _focused = f,
                headerStyle: const HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  todayDecoration: BoxDecoration(
                    border: Border.all(color: MilanacColors.gold),
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: const TextStyle(color: MilanacColors.gold),
                  selectedDecoration: const BoxDecoration(
                    color: MilanacColors.red,
                    shape: BoxShape.circle,
                  ),
                  weekendTextStyle: const TextStyle(color: Colors.white70),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) => events.isEmpty
                      ? null
                      : Positioned(
                          bottom: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final e in events.take(3))
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
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
              const Divider(),
              _SectionTitle(_dayTitle(_selected)),
              if (dayEvents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Nessun evento in questo giorno.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              for (final e in dayEvents)
                EventCard(event: e, editable: isDirettivo),
              if (upcoming.isNotEmpty) ...[
                const _SectionTitle('Prossimi appuntamenti'),
                for (final e in upcoming)
                  EventCard(event: e, editable: isDirettivo, showDate: true),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _dayTitle(DateTime d) {
    final s = DateFormat('EEEE d MMMM', 'it').format(d);
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
    ),
  );
}

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.editable,
    this.showDate = false,
  });
  final ClubEvent event;
  final bool editable;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat(
      showDate ? 'EEE d MMM · HH:mm' : 'HH:mm',
      'it',
    ).format(event.startsAt);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: event.type.color.withValues(alpha: 0.2),
          child: Icon(event.type.icon, color: event.type.color),
        ),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            time,
            event.type.label,
            if (event.location != null && event.location!.isNotEmpty)
              event.location!,
          ].join(' · '),
        ),
        trailing: event.team == null
            ? null
            : TeamBadge(event.team!, small: true),
        onTap: () => showEventDetails(context, event, editable: editable),
      ),
    );
  }
}
