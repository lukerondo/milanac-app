import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/italian_time.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/presenze/attendance.dart';
import 'package:milanac/features/presenze/evening.dart';

void main() {
  const solare = Duration(hours: 1);
  const legale = Duration(hours: 2);

  test('ora italiana: UTC+1 d\'inverno, UTC+2 d\'estate', () {
    expect(italianOffset(DateTime.utc(2026, 1, 15, 12)), solare);
    expect(italianOffset(DateTime.utc(2026, 7, 15, 12)), legale);
    expect(
      italianClock(DateTime.utc(2026, 1, 15, 12)),
      DateTime.utc(2026, 1, 15, 13),
    );
    expect(
      italianClock(DateTime.utc(2026, 7, 15, 12)),
      DateTime.utc(2026, 7, 15, 14),
    );
    // A cavallo di Capodanno conta il giorno italiano.
    expect(italianDay(DateTime.utc(2026, 12, 31, 23, 30)), DateTime(2027));
  });

  test('cambio d\'ora di marzo: ultima domenica, alle 01:00 UTC', () {
    // 2026: domenica 29 marzo (02:00 → 03:00); 2027: domenica 28 marzo.
    expect(
      italianClock(DateTime.utc(2026, 3, 29, 0, 59)),
      DateTime.utc(2026, 3, 29, 1, 59),
    );
    expect(
      italianClock(DateTime.utc(2026, 3, 29, 1)),
      DateTime.utc(2026, 3, 29, 3),
    );
    expect(italianOffset(DateTime.utc(2026, 3, 22, 12)), solare);
    expect(italianOffset(DateTime.utc(2027, 3, 28, 0, 59)), solare);
    expect(italianOffset(DateTime.utc(2027, 3, 28, 1)), legale);
    // Le 02:30 di quella notte non esistono: valgono come le 03:30.
    expect(
      fromItalianClock(DateTime.utc(2026, 3, 29, 2, 30)),
      DateTime.utc(2026, 3, 29, 1, 30),
    );
  });

  test('cambio d\'ora di ottobre: ultima domenica, alle 01:00 UTC', () {
    // 2026: domenica 25 ottobre (03:00 → 02:00); 2027: domenica 31 ottobre.
    expect(
      italianClock(DateTime.utc(2026, 10, 25, 0, 59)),
      DateTime.utc(2026, 10, 25, 2, 59),
    );
    expect(
      italianClock(DateTime.utc(2026, 10, 25, 1)),
      DateTime.utc(2026, 10, 25, 2),
    );
    expect(italianOffset(DateTime.utc(2026, 10, 18, 12)), legale);
    expect(italianOffset(DateTime.utc(2027, 10, 31, 0, 59)), legale);
    expect(italianOffset(DateTime.utc(2027, 10, 31, 1)), solare);
    // Le 02:30 di quella notte capitano due volte: vale la prima.
    expect(
      fromItalianClock(DateTime.utc(2026, 10, 25, 2, 30)),
      DateTime.utc(2026, 10, 25, 0, 30),
    );
  });

  test('dall\'ora italiana all\'istante e ritorno', () {
    for (final clock in [
      DateTime.utc(2026),
      DateTime.utc(2026, 3, 29, 1, 59),
      DateTime.utc(2026, 3, 29, 3),
      DateTime.utc(2026, 6, 30, 18, 30),
      DateTime.utc(2026, 10, 25, 3),
      DateTime.utc(2026, 12, 31, 23, 59),
    ]) {
      expect(italianClock(fromItalianClock(clock)), clock, reason: '$clock');
    }
  });

  test('scadenza delle 18:30 italiane nei giorni del cambio d\'ora', () {
    // Sabato 28 marzo ancora ora solare, domenica 29 già ora legale.
    expect(
      attendanceDeadline(DateTime(2026, 3, 28)),
      DateTime.utc(2026, 3, 28, 17, 30),
    );
    expect(
      attendanceDeadline(DateTime(2026, 3, 29)),
      DateTime.utc(2026, 3, 29, 16, 30),
    );
    // Sabato 24 ottobre ancora ora legale, domenica 25 di nuovo ora solare.
    expect(
      attendanceDeadline(DateTime(2026, 10, 24)),
      DateTime.utc(2026, 10, 24, 16, 30),
    );
    expect(
      attendanceDeadline(DateTime(2026, 10, 25)),
      DateTime.utc(2026, 10, 25, 17, 30),
    );

    final marzo = DateTime(2026, 3, 29);
    expect(answersOpen(marzo, DateTime.utc(2026, 3, 29, 16, 29)), isTrue);
    expect(answersOpen(marzo, DateTime.utc(2026, 3, 29, 16, 30)), isFalse);
    final ottobre = DateTime(2026, 10, 25);
    expect(answersOpen(ottobre, DateTime.utc(2026, 10, 25, 17, 29)), isTrue);
    expect(answersOpen(ottobre, DateTime.utc(2026, 10, 25, 17, 30)), isFalse);
  });

  test('telefono su un altro fuso: contano il giorno e la scadenza italiani', () {
    final lunedi = DateTime(2026, 10, 12);
    // New York (UTC-4), lunedì alle 13:00: in Italia sono le 19:00.
    final newYork = DateTime.parse('2026-10-12T13:00:00-04:00');
    expect(italianDay(newYork), lunedi);
    expect(answersOpen(lunedi, newYork), isFalse);
    // Tokyo (UTC+9), martedì 13 all'01:00: in Italia è ancora lunedì, le 18:00.
    final tokyo = DateTime.parse('2026-10-13T01:00:00+09:00');
    expect(italianDay(tokyo), lunedi);
    expect(italianClock(tokyo).hour, 18);
    expect(answersOpen(lunedi, tokyo), isTrue);
    // Londra (UTC+1 d'estate), lunedì alle 17:45: in Italia sono le 18:45.
    expect(
      answersOpen(lunedi, DateTime.parse('2026-10-12T17:45:00+01:00')),
      isFalse,
    );
  });

  test('eventi: dal database in ora italiana e ritorno', () {
    final ottobre = ClubEvent.fromMap({
      'id': 'a',
      'type': 'amichevole',
      'title': 'Amichevole',
      'starts_at': '2026-10-14T19:30:00+00:00',
    });
    expect(ottobre.startsAt, DateTime.utc(2026, 10, 14, 21, 30));
    expect(ottobre.toMap()['starts_at'], '2026-10-14T19:30:00.000Z');
    final dicembre = ClubEvent.fromMap({
      'id': 'b',
      'type': 'torneo',
      'title': 'Torneo',
      'starts_at': '2026-12-01T20:30:00Z',
    });
    expect(dicembre.startsAt, DateTime.utc(2026, 12, 1, 21, 30));
    // L'allenamento automatico è sempre alle 21:30 italiane.
    expect(
      fromItalianClock(trainingOn(DateTime(2026, 10, 14)).startsAt),
      DateTime.utc(2026, 10, 14, 19, 30),
    );
    expect(
      fromItalianClock(trainingOn(DateTime(2026, 12, 1)).startsAt),
      DateTime.utc(2026, 12, 1, 20, 30),
    );
  });
}
