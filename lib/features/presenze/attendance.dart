import '../../core/config.dart';

enum AttendanceStatus {
  presente('Presente'),
  ritardo('In ritardo'),
  assente('Assente');

  const AttendanceStatus(this.label);
  final String label;
}

/// Presenza di un giocatore per una serata (tabella `attendance`).
class AttendanceEntry {
  const AttendanceEntry({
    required this.playerId,
    required this.date,
    required this.status,
    this.arrivalTime = AppConfig.defaultArrivalTime,
    this.note,
  });

  final String playerId;

  /// Solo giorno (ora a mezzanotte).
  final DateTime date;
  final AttendanceStatus status;

  /// Formato "HH:mm".
  final String arrivalTime;
  final String? note;

  bool get isPresent => status != AttendanceStatus.assente;

  factory AttendanceEntry.fromMap(Map<String, dynamic> m) => AttendanceEntry(
    playerId: m['player_id'] as String,
    date: DateTime.parse(m['date'] as String),
    status: AttendanceStatus.values.byName(m['status'] as String),
    arrivalTime:
        ((m['arrival_time'] as String?) ?? AppConfig.defaultArrivalTime)
            .substring(0, 5),
    note: m['note'] as String?,
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

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Statistiche dello storico di un giocatore.
class AttendanceStats {
  AttendanceStats(List<AttendanceEntry> entries)
    : total = entries.length,
      present = entries
          .where((e) => e.status == AttendanceStatus.presente)
          .length,
      late = entries.where((e) => e.status == AttendanceStatus.ritardo).length,
      absent = entries
          .where((e) => e.status == AttendanceStatus.assente)
          .length;

  final int total;
  final int present;
  final int late;
  final int absent;

  /// Percentuale di serate in cui il giocatore c'era (anche in ritardo).
  int get percent =>
      total == 0 ? 0 : (((present + late) / total) * 100).round();
}
