import '../../core/config.dart';
import '../../core/italian_time.dart';

enum AttendanceStatus {
  presente('Presente'),
  ritardo('In ritardo'),
  assente('Assente');

  const AttendanceStatus(this.label);
  final String label;
}

/// Ora entro cui rispondere per la serata, in ora italiana come sul server.
const attendanceDeadlineHour = 18;
const attendanceDeadlineMinute = 30;
const attendanceDeadlineLabel = '18:30';

/// L'istante in cui chiudono le risposte per [day]: le 18:30 italiane di quel giorno,
/// qualunque sia il fuso del telefono.
DateTime attendanceDeadline(DateTime day) => fromItalianClock(
  DateTime.utc(
    day.year,
    day.month,
    day.day,
    attendanceDeadlineHour,
    attendanceDeadlineMinute,
  ),
);

/// Le risposte di un giorno sono aperte finché non scatta la sua scadenza
/// (per i giorni successivi si può rispondere in anticipo). [now] è un istante.
bool answersOpen(DateTime day, [DateTime? now]) =>
    (now ?? DateTime.now()).isBefore(attendanceDeadline(day));

/// Presenza di un giocatore per una serata (tabella `attendance`).
class AttendanceEntry {
  const AttendanceEntry({
    required this.playerId,
    required this.date,
    required this.status,
    this.arrivalTime = AppConfig.defaultArrivalTime,
    this.note,
    this.auto = false,
    this.setBy,
  });

  final String playerId;

  /// Solo giorno (ora a mezzanotte).
  final DateTime date;
  final AttendanceStatus status;

  /// Formato "HH:mm".
  final String arrivalTime;
  final String? note;

  /// Assenza segnata in automatico alle 18:30 perché non ha risposto.
  final bool auto;

  /// Chi ha scritto la risposta per conto del giocatore (il Direttivo), se non lui stesso.
  final String? setBy;

  bool get isPresent => status != AttendanceStatus.assente;

  factory AttendanceEntry.fromMap(Map<String, dynamic> m) => AttendanceEntry(
    playerId: m['player_id'] as String,
    date: DateTime.parse(m['date'] as String),
    status: AttendanceStatus.values.byName(m['status'] as String),
    arrivalTime:
        ((m['arrival_time'] as String?) ?? AppConfig.defaultArrivalTime)
            .substring(0, 5),
    note: m['note'] as String?,
    auto: (m['auto'] as bool?) ?? false,
    setBy: m['set_by'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'player_id': playerId,
    'date': dateKey(date),
    'status': status.name,
    'arrival_time': arrivalTime,
    'note': note,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lo storico di [playerId] fino a [today] compreso, dal più recente: le risposte date in
/// anticipo per i giorni successivi non contano (come sul server, in player_stats).
List<AttendanceEntry> historyOf(
  String playerId,
  Iterable<AttendanceEntry> entries,
  DateTime today,
) =>
    entries
        .where((e) => e.playerId == playerId && !e.date.isAfter(today))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

/// Presenti, in ritardo, assenti e senza risposta di una serata tra [memberIds]:
/// le risposte degli altri (l'altra squadra, chi non è più nella rosa) non contano.
class DayCounts {
  const DayCounts._(this.present, this.late, this.absent, this.waiting);

  /// [ofDay]: le risposte della serata, per giocatore.
  factory DayCounts(
    Iterable<String> memberIds,
    Map<String, AttendanceEntry> ofDay,
  ) {
    var present = 0, late = 0, absent = 0, waiting = 0;
    for (final id in memberIds) {
      switch (ofDay[id]?.status) {
        case AttendanceStatus.presente:
          present++;
        case AttendanceStatus.ritardo:
          late++;
        case AttendanceStatus.assente:
          absent++;
        case null:
          waiting++;
      }
    }
    return DayCounts._(present, late, absent, waiting);
  }

  final int present;
  final int late;
  final int absent;
  final int waiting;
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Statistiche dello storico di un giocatore (le assenze automatiche contano come assenze).
class AttendanceStats {
  AttendanceStats(List<AttendanceEntry> entries)
    : total = entries.length,
      present = entries
          .where((e) => e.status == AttendanceStatus.presente)
          .length,
      late = entries.where((e) => e.status == AttendanceStatus.ritardo).length,
      absent = entries
          .where((e) => e.status == AttendanceStatus.assente)
          .length,
      autoAbsent = entries.where((e) => e.auto).length;

  final int total;
  final int present;
  final int late;
  final int absent;
  final int autoAbsent;

  /// Percentuale di serate in cui il giocatore c'era (anche in ritardo).
  int get percent =>
      total == 0 ? 0 : (((present + late) / total) * 100).round();
}
