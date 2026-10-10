import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import 'attendance.dart';

/// Quanti giorni di storico caricare.
const historyDays = 60;

abstract class AttendanceRepository {
  /// Tutte le presenze dal giorno [from] in poi, aggiornate in tempo reale.
  Stream<List<AttendanceEntry>> watchSince(DateTime from);
  Future<void> save(AttendanceEntry entry);
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  if (AppConfig.isDemo) return DemoAttendanceRepository();
  return _SupabaseAttendanceRepository(ref);
});

final attendanceProvider = StreamProvider<List<AttendanceEntry>>((ref) {
  final from = dayOnly(DateTime.now())
      .subtract(const Duration(days: historyDays));
  return ref.watch(attendanceRepositoryProvider).watchSince(from);
});

class _SupabaseAttendanceRepository implements AttendanceRepository {
  _SupabaseAttendanceRepository(this._ref);
  final Ref _ref;

  @override
  Stream<List<AttendanceEntry>> watchSince(DateTime from) => _ref
      .read(supabaseProvider)
      .from('attendance')
      .stream(primaryKey: ['id'])
      .gte('date', dateKey(from))
      .map((rows) => rows.map(AttendanceEntry.fromMap).toList());

  @override
  Future<void> save(AttendanceEntry e) async {
    await _ref
        .read(supabaseProvider)
        .from('attendance')
        .upsert(e.toMap(), onConflict: 'player_id,date');
  }
}

/// Storico di esempio in memoria (modalità demo e test).
class DemoAttendanceRepository implements AttendanceRepository {
  DemoAttendanceRepository() {
    final today = dayOnly(DateTime.now());
    const pattern = {
      'p2': [
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.ritardo,
        AttendanceStatus.presente,
        AttendanceStatus.assente,
        AttendanceStatus.presente,
      ],
      'p3': [
        AttendanceStatus.presente,
        AttendanceStatus.assente,
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.ritardo,
      ],
      'p4': [
        AttendanceStatus.ritardo,
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.assente,
        AttendanceStatus.assente,
        AttendanceStatus.presente,
      ],
      'demo': [
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.presente,
        AttendanceStatus.ritardo,
        AttendanceStatus.presente,
      ],
    };
    pattern.forEach((player, statuses) {
      for (final (i, s) in statuses.indexed) {
        _entries.add(
          AttendanceEntry(
            playerId: player,
            date: today.subtract(Duration(days: 2 * (i + 1))),
            status: s,
            arrivalTime: s == AttendanceStatus.ritardo
                ? '22:00'
                : AppConfig.defaultArrivalTime,
          ),
        );
      }
    });
    // Stasera: un giocatore ha già risposto.
    _entries.add(
      AttendanceEntry(
        playerId: 'p2',
        date: today,
        status: AttendanceStatus.ritardo,
        arrivalTime: '21:50',
        note: 'Esco tardi da lavoro',
      ),
    );
  }

  final _entries = <AttendanceEntry>[];
  final _controller = StreamController<List<AttendanceEntry>>.broadcast();

  void _emit() => _controller.add(List.of(_entries));

  @override
  Stream<List<AttendanceEntry>> watchSince(DateTime from) async* {
    yield List.of(_entries);
    yield* _controller.stream;
  }

  @override
  Future<void> save(AttendanceEntry e) async {
    _entries.removeWhere(
      (x) => x.playerId == e.playerId && x.date == dayOnly(e.date),
    );
    _entries.add(
      AttendanceEntry(
        playerId: e.playerId,
        date: dayOnly(e.date),
        status: e.status,
        arrivalTime: e.arrivalTime,
        note: e.note,
        // Come il database: chi risponde per un altro (il Direttivo) resta registrato.
        setBy: e.playerId == 'demo' ? null : 'demo',
      ),
    );
    _emit();
  }
}
