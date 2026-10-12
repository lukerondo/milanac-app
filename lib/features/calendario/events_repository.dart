import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/config.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import 'club_event.dart';

abstract class EventsRepository {
  /// Tutti gli eventi, dal primo all'ultimo, aggiornati in tempo reale.
  Stream<List<ClubEvent>> watchAll();

  /// Crea l'evento se [ClubEvent.id] è vuoto, altrimenti lo aggiorna.
  Future<void> save(ClubEvent event);
  Future<void> delete(String id);
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  if (AppConfig.isDemo) {
    return DemoEventsRepository(now: ref.read(clockProvider)());
  }
  return _SupabaseEventsRepository(ref);
});

/// Gli eventi letti con i permessi dell'utente: si ricaricano quando entra un altro account.
final eventsProvider = StreamProvider<List<ClubEvent>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const []);
  return ref.watch(eventsRepositoryProvider).watchAll();
});

/// Dal primo all'ultimo: l'ordine di arrivo dal server non conta.
List<ClubEvent> sortedByStart(Iterable<ClubEvent> events) =>
    events.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

class _SupabaseEventsRepository implements EventsRepository {
  _SupabaseEventsRepository(this._ref);
  final Ref _ref;

  @override
  Stream<List<ClubEvent>> watchAll() => _ref
      .read(supabaseProvider)
      .from('events')
      .stream(primaryKey: ['id'])
      // Senza ascending lo stream ordina dal più lontano (default false).
      .order('starts_at', ascending: true)
      .map((rows) => sortedByStart(rows.map(ClubEvent.fromMap)));

  @override
  Future<void> save(ClubEvent e) async {
    final client = _ref.read(supabaseProvider);
    if (e.id.isEmpty) {
      await client.from('events').insert({
        ...e.toMap(),
        'created_by': client.auth.currentUser?.id,
      });
    } else {
      await client.from('events').update(e.toMap()).eq('id', e.id);
    }
  }

  @override
  Future<void> delete(String id) async {
    await _ref.read(supabaseProvider).from('events').delete().eq('id', id);
  }
}

/// Eventi di esempio in memoria (modalità demo e test), intorno al giorno italiano di [now].
class DemoEventsRepository implements EventsRepository {
  DemoEventsRepository({DateTime? now}) {
    final today = italianClock(now ?? DateTime.now());
    // Ore italiane, come gli eventi letti dal server.
    DateTime at(int days, [int h = 21, int m = 30]) =>
        DateTime.utc(today.year, today.month, today.day + days, h, m);
    _events.addAll([
      ClubEvent(
        id: 'e1',
        type: EventType.torneo,
        title: 'FVPA – 3ª giornata vs Atletico Virtuale',
        startsAt: at(2),
        location: 'PlayStation 5',
        description: 'Ritrovo in lobby alle 21:15.',
      ),
      ClubEvent(
        id: 'e2',
        type: EventType.allenamento,
        title: 'Allenamento schemi calci piazzati',
        startsAt: at(4, 21, 0),
      ),
      ClubEvent(
        id: 'e3',
        team: Team.futuro,
        type: EventType.amichevole,
        title: 'Amichevole vs Real Brianza',
        startsAt: at(6),
      ),
      ClubEvent(
        id: 'e4',
        type: EventType.riunione,
        title: 'Riunione direttivo – mercato',
        startsAt: at(9, 22, 30),
        location: 'Discord',
      ),
      ClubEvent(
        id: 'e5',
        type: EventType.torneo,
        title: 'FVPA – 2ª giornata vs Dinamo Pixel',
        startsAt: at(-5),
      ),
    ]);
  }

  final _events = <ClubEvent>[];
  final _controller = StreamController<List<ClubEvent>>.broadcast();
  var _nextId = 100;

  List<ClubEvent> get _sorted => sortedByStart(_events);

  @override
  Stream<List<ClubEvent>> watchAll() async* {
    yield _sorted;
    yield* _controller.stream;
  }

  @override
  Future<void> save(ClubEvent e) async {
    _events.removeWhere((x) => x.id == e.id);
    _events.add(
      e.id.isEmpty
          ? ClubEvent(
              id: 'e${_nextId++}',
              type: e.type,
              title: e.title,
              startsAt: e.startsAt,
              description: e.description,
              location: e.location,
              team: e.team,
            )
          : e,
    );
    _controller.add(_sorted);
  }

  @override
  Future<void> delete(String id) async {
    _events.removeWhere((x) => x.id == id);
    _controller.add(_sorted);
  }
}
