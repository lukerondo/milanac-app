import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/italian_time.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/calendario/events_repository.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/presenze/attendance_repository.dart';
import 'package:milanac/features/presenze/attendance_ui.dart';
import 'package:milanac/features/presenze/presenze_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'helpers.dart';
import 'home_test.dart' show italyAt, startAppAt, todayInItalyAt;

/// L'account entrato sul telefono (null = nessuno).
class TestAccount extends Notifier<String?> {
  @override
  String? build() => 'a';
  void enter(String? id) => state = id;
}

final testAccountProvider = NotifierProvider<TestAccount, String?>(
  TestAccount.new,
);

class _CountingAttendance extends DemoAttendanceRepository {
  var reads = 0;

  @override
  Stream<List<AttendanceEntry>> watchSince(DateTime from) {
    reads++;
    return super.watchSince(from);
  }
}

class _CountingEvents extends DemoEventsRepository {
  var reads = 0;

  @override
  Stream<List<ClubEvent>> watchAll() {
    reads++;
    return super.watchAll();
  }
}

Future<ProviderContainer> openPresenze(
  WidgetTester tester,
  DateTime now,
) async {
  final container = await startAppAt(tester, now);
  await goToSection(tester, 'Presenze');
  return container;
}

/// I titoli degli elenchi della serata, in ordine ("PRESENTI · 1", …).
List<String> groups(WidgetTester tester) => [
  for (final g in tester.widgetList<AttendanceGroupLabel>(
    find.byType(AttendanceGroupLabel),
  ))
    '${g.title.toUpperCase()} · ${g.count}',
];

/// Il giorno della settimana in alto: "Lunedì 12, oggi" (e "partita" o "evento").
Finder dayTile(String label) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}(,|\$)'));

/// Scorre la lista del giorno fino a [finder] (in su con [delta] negativo).
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 150,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('presenze-giorno')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('statistiche: il ritardo conta come presenza, l\'assenza automatica '
      'come assenza', () {
    final d = DateTime(2026, 10, 1);
    final stats = AttendanceStats([
      AttendanceEntry(
        playerId: 'x',
        date: d,
        status: AttendanceStatus.presente,
      ),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.ritardo),
      AttendanceEntry(playerId: 'x', date: d, status: AttendanceStatus.assente),
      AttendanceEntry(
        playerId: 'x',
        date: d,
        status: AttendanceStatus.assente,
        auto: true,
      ),
    ]);
    expect(stats.percent, 50);
    expect(stats.late, 1);
    expect(stats.absent, 2);
    expect(stats.autoAbsent, 1);
  });

  testWidgets('calendario: la serata di oggi, gli elenchi e la risposta', (
    tester,
  ) async {
    await openPresenze(tester, todayInItalyAt(17));
    expect(find.text('OGGI · MILAN AC'), findsOneWidget);
    expect(find.text('ALLENAMENTO 21:30'), findsOneWidget);
    expect(find.text('La tua risposta, entro le 18:30'), findsOneWidget);
    await scrollTo(tester, find.text('SENZA RISPOSTA · 3'));
    await scrollTo(
      tester,
      find.text('Arrivo alle 21:50 · Esco tardi da lavoro'),
    );

    await scrollTo(
      tester,
      find.widgetWithText(OutlinedButton, 'Presente'),
      delta: -150,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente').first);
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Presente'), findsOneWidget);
    await scrollTo(tester, find.text('SENZA RISPOSTA · 2'));
    await scrollTo(tester, find.text('PRESENTI · 1'));
  });

  testWidgets('ritardo con nota obbligatoria; assenza e storico', (
    tester,
  ) async {
    await openPresenze(tester, todayInItalyAt(17));

    await scrollTo(tester, find.widgetWithText(OutlinedButton, 'Ritardo'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ritardo').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // orario proposto: 22:00
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.text('Scrivi il motivo del ritardo.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Lavoro');
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(
      find.text('La tua risposta: In ritardo, arrivo alle 22:00 · Lavoro'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Assente').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Febbre');
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Assente · Febbre'), findsOneWidget);

    // Lo storico di Marco Rossi, con i pulsanti del Direttivo.
    await scrollTo(tester, find.text('Marco Rossi'));
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Storico presenze'), findsOneWidget);
    expect(find.textContaining('Segna per questo giocatore'), findsOneWidget);
  });

  testWidgets('dopo le 18:30 i pulsanti sono spenti', (tester) async {
    await openPresenze(tester, todayInItalyAt(18, 31));
    await scrollTo(tester, find.textContaining('Risposte chiuse alle 18:30'));
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Presente').first,
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Statistiche'));
    await tester.pumpAndSettle();
    expect(find.textContaining('puntuale'), findsWidgets);
  });

  test('riepilogo: contano solo i membri mostrati', () {
    final d = DateTime(2026, 10, 12);
    AttendanceEntry answer(String id, AttendanceStatus s) =>
        AttendanceEntry(playerId: id, date: d, status: s);
    final counts = DayCounts(
      ['a', 'b', 'c'],
      {
        'a': answer('a', AttendanceStatus.presente),
        'b': answer('b', AttendanceStatus.ritardo),
        // Dell'altra squadra o non più nella rosa: non contano.
        'x': answer('x', AttendanceStatus.presente),
        'y': answer('y', AttendanceStatus.assente),
      },
    );
    expect(
      (counts.present, counts.late, counts.absent, counts.waiting),
      (1, 1, 0, 1),
    );
  });

  test('storico fino a oggi: le risposte date in anticipo non contano', () {
    final today = DateTime(2026, 10, 12);
    AttendanceEntry answer(String id, int day, AttendanceStatus s) =>
        AttendanceEntry(playerId: id, date: DateTime(2026, 10, day), status: s);
    final history = historyOf('a', [
      answer('a', 10, AttendanceStatus.presente),
      answer('a', 12, AttendanceStatus.presente),
      answer('a', 13, AttendanceStatus.assente),
      answer('b', 11, AttendanceStatus.assente),
    ], today);
    expect([for (final e in history) e.date.day], [12, 10]);
    expect(AttendanceStats(history).percent, 100);
  });

  test('risposta dopo le 18:30: il messaggio lo dice in chiaro', () {
    const rls = PostgrestException(
      message:
          'new row violates row-level security policy for table '
          '"attendance"',
      code: '42501',
    );
    expect(
      answerErrorText(rls, mine: true),
      'Le risposte per stasera si sono chiuse alle 18:30 (ora italiana).',
    );
    // Per un altro giocatore è un permesso che manca.
    expect(answerErrorText(rls, mine: false), contains('non hai il permesso'));
    expect(
      answerErrorText(Exception('SocketException: rete'), mine: true),
      'Nessuna connessione: controlla la rete e riprova.',
    );
  });

  test(
    'presenze ed eventi si rileggono quando entra un altro account',
    () async {
      final attendance = _CountingAttendance();
      final events = _CountingEvents();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith(
            (ref) => ref.watch(testAccountProvider),
          ),
          attendanceRepositoryProvider.overrideWithValue(attendance),
          eventsRepositoryProvider.overrideWithValue(events),
        ],
      );
      addTearDown(container.dispose);
      container.listen(attendanceProvider, (_, _) {});
      container.listen(eventsProvider, (_, _) {});
      await container.read(attendanceProvider.future);
      await container.read(eventsProvider.future);
      expect((attendance.reads, events.reads), (1, 1));

      container.read(testAccountProvider.notifier).enter('b');
      expect(await container.read(attendanceProvider.future), isNotEmpty);
      expect(await container.read(eventsProvider.future), isNotEmpty);
      expect((attendance.reads, events.reads), (2, 2));

      // Uscito dall'account: niente dati (e niente letture con i permessi di prima).
      container.read(testAccountProvider.notifier).enter(null);
      expect(await container.read(attendanceProvider.future), isEmpty);
      expect(await container.read(eventsProvider.future), isEmpty);
      expect((attendance.reads, events.reads), (2, 2));
    },
  );

  test('i giorni fuori dal calendario si riportano dentro', () {
    final today = DateTime(2026, 10, 12);
    expect(calendarLastDay(today), DateTime(2029, 12, 31));
    expect(
      clampToCalendar(DateTime(2040, 6, 1), today),
      DateTime(2029, 12, 31),
    );
    expect(clampToCalendar(DateTime(2019, 5, 1), today), DateTime(2024));
    expect(
      clampToCalendar(DateTime.utc(2026, 11, 3, 21, 30), today),
      DateTime(2026, 11, 3),
    );
  });

  testWidgets('riepilogo del FUTURO: non contano le risposte del Milan AC', (
    tester,
  ) async {
    await openPresenze(tester, todayInItalyAt(17));
    await scrollTo(tester, find.widgetWithText(OutlinedButton, 'Presente'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente').first);
    await tester.pumpAndSettle();
    // Milan AC: io presente, Marco Rossi in ritardo, Neri e Bianchi senza risposta.
    expect(groups(tester), [
      'PRESENTI · 1',
      'IN RITARDO · 1',
      'SENZA RISPOSTA · 2',
    ]);

    // Futuro: Andrea Neri e Paolo Verdi non hanno ancora risposto.
    await scrollTo(tester, find.text('Futuro'), delta: -150);
    await tester.tap(find.text('Futuro'));
    await tester.pumpAndSettle();
    expect(groups(tester), ['SENZA RISPOSTA · 2']);
  });

  testWidgets('la risposta data in anticipo non cambia la percentuale', (
    tester,
  ) async {
    final now = todayInItalyAt(17);
    final container = await openPresenze(tester, now);
    final today = italianDay(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    container.read(routerProvider).go('/presenze?giorno=${dateKey(tomorrow)}');
    await tester.pumpAndSettle();
    final label = DateFormat('EEEE d MMMM', 'it').format(tomorrow);
    expect(find.text('${label.toUpperCase()} · MILAN AC'), findsOneWidget);

    await scrollTo(tester, find.widgetWithText(OutlinedButton, 'Assente'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Assente').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Assente'), findsOneWidget);

    // Lo storico arriva fino a oggi: 5 presenze e un ritardo, sempre il 100%.
    await scrollTo(tester, find.text('Demo Direttivo (tu)'));
    await tester.tap(find.text('Demo Direttivo (tu)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Storico presenze'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets(
    'telefono su un altro fuso: il giorno e gli orari sono italiani',
    (tester) async {
      // Tokyo, martedì 13 ottobre all'01:00: in Italia è lunedì 12, le 18:00.
      await openPresenze(tester, DateTime.parse('2026-10-13T01:00:00+09:00'));
      expect(dayTile('Lunedì 12, oggi'), findsOneWidget);
      expect(find.text('OGGI · MILAN AC'), findsOneWidget);
      expect(find.text('ALLENAMENTO 21:30'), findsOneWidget);
      expect(find.text('La tua risposta, entro le 18:30'), findsOneWidget);
    },
  );

  testWidgets('telefono su un altro fuso: alle 18:45 italiane è chiuso', (
    tester,
  ) async {
    // New York, lunedì 12 ottobre alle 12:45: in Italia sono le 18:45.
    await openPresenze(tester, DateTime.parse('2026-10-12T12:45:00-04:00'));
    expect(dayTile('Lunedì 12, oggi'), findsOneWidget);
    expect(find.text('OGGI · MILAN AC'), findsOneWidget);
    await scrollTo(tester, find.textContaining('Risposte chiuse alle 18:30'));
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Presente').first,
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('cambio d\'ora di marzo: si chiude alle 18:30 italiane', (
    tester,
  ) async {
    // Domenica 29 marzo 2026, ora legale da stanotte: le 18:35 sono le 16:35 UTC.
    await openPresenze(tester, italyAt(2026, 3, 29, 18, 35));
    expect(find.text('MARZO 2026'), findsOneWidget);
    expect(dayTile('Domenica 29, oggi'), findsOneWidget);
    await scrollTo(tester, find.textContaining('Risposte chiuse alle 18:30'));
  });

  testWidgets('la riga cambia elenco mentre lo storico è aperto: la correzione '
      'del Direttivo si salva lo stesso', (tester) async {
    final now = todayInItalyAt(18, 29);
    final container = await openPresenze(tester, now);
    await scrollTo(tester, find.text('Luca Bianchi'));
    await tester.tap(find.text('Luca Bianchi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Segna per questo giocatore'), findsOneWidget);

    // Alle 18:30 l'assenza automatica lo sposta tra gli assenti.
    await container
        .read(attendanceRepositoryProvider)
        .save(
          AttendanceEntry(
            playerId: 'p3',
            date: italianDay(now),
            status: AttendanceStatus.assente,
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Risposta non salvata'), findsNothing);
    expect(find.textContaining('Storico presenze'), findsNothing);
    await scrollTo(tester, find.text('PRESENTI · 1'));
  });

  testWidgets(
    'il promemoria riporta a oggi anche dopo una scelta nella pagina',
    (tester) async {
      final container = await openPresenze(tester, italyAt(2026, 10, 12, 17));
      final router = container.read(routerProvider);
      expect(find.text('OGGI · MILAN AC'), findsOneWidget);

      // Un altro giorno scelto toccandolo: la rotta lo segue.
      final wednesday = find.byWidgetPredicate(
        (w) =>
            w.runtimeType.toString() == '_DayTile' &&
            (w as dynamic).day == DateTime(2026, 10, 14),
      );
      await tester.tap(wednesday);
      await tester.pumpAndSettle();
      expect(find.text('MERCOLEDÌ 14 OTTOBRE · MILAN AC'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/presenze?giorno=2026-10-14',
      );

      // La notifica delle 18:00 apre `/presenze`: si torna a oggi.
      router.go('/presenze');
      await tester.pumpAndSettle();
      expect(find.text('OGGI · MILAN AC'), findsOneWidget);

      // Lo stesso con le statistiche aperte.
      await tester.tap(find.text('Statistiche'));
      await tester.pumpAndSettle();
      expect(find.textContaining('puntuale'), findsWidgets);
      router.go('/presenze');
      await tester.pumpAndSettle();
      expect(find.text('OGGI · MILAN AC'), findsOneWidget);
    },
  );

  testWidgets('passata la mezzanotte, il promemoria delle 18:00 apre il giorno '
      'nuovo', (tester) async {
    var now = italyAt(2026, 10, 12, 23, 50);
    final container = await startAppAt(tester, now, clock: () => now);
    await goToSection(tester, 'Presenze');
    expect(find.text('OGGI · MILAN AC'), findsOneWidget);

    // L'app resta aperta (o in memoria) fino al giorno dopo; la notifica riporta alla
    // stessa rotta.
    now = italyAt(2026, 10, 13, 18);
    await tester.pump(const Duration(minutes: 1));
    container.read(routerProvider).go('/presenze');
    await tester.pumpAndSettle();
    expect(find.text('OGGI · MILAN AC'), findsOneWidget);
    expect(find.text('LUNEDÌ 12 OTTOBRE · MILAN AC'), findsNothing);
    expect(find.text('La tua risposta, entro le 18:30'), findsOneWidget);
  });

  testWidgets('giorno chiesto fuori dal calendario: si apre il più vicino', (
    tester,
  ) async {
    final container = await openPresenze(tester, italyAt(2026, 10, 12, 17));
    container.read(routerProvider).go('/presenze?giorno=2040-06-01');
    await tester.pumpAndSettle();
    expect(find.text('DICEMBRE 2029'), findsOneWidget);
    expect(find.text('LUNEDÌ 31 DICEMBRE · MILAN AC'), findsOneWidget);

    container.read(routerProvider).go('/presenze?giorno=2019-05-01');
    await tester.pumpAndSettle();
    expect(find.text('GENNAIO 2024'), findsOneWidget);
  });
}
