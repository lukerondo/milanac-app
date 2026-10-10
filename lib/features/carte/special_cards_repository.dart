import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/config.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../risultati/match.dart';

/// Tipo di carta speciale: la nero/oro della settimana (assegnata dal Direttivo, una per
/// reparto) e la blu elettrico (automatica: tripletta, o tre partite ufficiali di fila
/// senza subire gol). Durano 7 giorni e sostituiscono la carta normale.
enum CardSpecial {
  neroOro('nero_oro', 'Nero/oro', 'CARTA DELLA SETTIMANA', MilanacColors.gold),
  blu('blu', 'Blu elettrico', 'BLU ELETTRICO', Color(0xFF3D8BFF));

  const CardSpecial(this.db, this.label, this.cardLabel, this.color);

  /// Nome nel database.
  final String db;
  final String label;

  /// Scritta in alto sulla carta.
  final String cardLabel;
  final Color color;

  IconData get icon =>
      this == blu ? Icons.bolt_rounded : Icons.military_tech_rounded;

  static CardSpecial? parse(Object? v) =>
      values.where((k) => k.db == v).firstOrNull;
}

/// I reparti premiati, nell'ordine in cui si mostrano.
const reparti = ['POR', 'DIF', 'CEN', 'ATT'];
const repartoLabels = {
  'POR': 'Portiere',
  'DIF': 'Difesa',
  'CEN': 'Centrocampo',
  'ATT': 'Attacco',
};

/// Carta speciale ricevuta da un giocatore (tabella `special_cards`).
class SpecialCard {
  const SpecialCard({
    required this.id,
    required this.playerId,
    required this.kind,
    required this.reparto,
    required this.startsAt,
    required this.endsAt,
    this.bonus = 5,
    this.reason,
    this.matchId,
    this.team,
    this.assignedBy,
  });

  final String id;
  final String playerId;
  final CardSpecial kind;
  final String reparto;

  /// Punti aggiunti all'overall (1–5).
  final int bonus;
  final String? reason;
  final String? matchId;
  final Team? team;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? assignedBy;

  bool get isBlue => kind == CardSpecial.blu;
  bool activeAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);

  SpecialCard copyWith({int? bonus, String? reparto}) => SpecialCard(
    id: id,
    playerId: playerId,
    kind: kind,
    reparto: reparto ?? this.reparto,
    startsAt: startsAt,
    endsAt: endsAt,
    bonus: bonus ?? this.bonus,
    reason: reason,
    matchId: matchId,
    team: team,
    assignedBy: assignedBy,
  );

  factory SpecialCard.fromMap(Map<String, dynamic> m) => SpecialCard(
    id: m['id'] as String,
    playerId: m['player_id'] as String,
    kind: CardSpecial.parse(m['kind']) ?? CardSpecial.neroOro,
    reparto: m['reparto'] as String,
    bonus: (m['bonus'] as num?)?.toInt() ?? 5,
    reason: m['reason'] as String?,
    matchId: m['match_id'] as String?,
    team: Team.parse(m['team']),
    startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(m['ends_at'] as String).toLocal(),
    assignedBy: m['assigned_by'] as String?,
  );
}

/// Ordine di presentazione: per reparto, poi la blu prima della nero/oro.
int compareCards(SpecialCard a, SpecialCard b) {
  final r = reparti.indexOf(a.reparto).compareTo(reparti.indexOf(b.reparto));
  if (r != 0) return r;
  if (a.isBlue != b.isBlue) return a.isBlue ? -1 : 1;
  return b.startsAt.compareTo(a.startsAt);
}

/// La carta valida adesso per ogni giocatore: la blu ha la precedenza, poi la più recente.
Map<String, SpecialCard> activeSpecialCards(
  Iterable<SpecialCard> cards,
  DateTime now,
) {
  final best = <String, SpecialCard>{};
  for (final c in cards.where((c) => c.activeAt(now))) {
    final current = best[c.playerId];
    if (current == null ||
        (c.isBlue && !current.isBlue) ||
        (c.isBlue == current.isBlue && c.startsAt.isAfter(current.startsAt))) {
      best[c.playerId] = c;
    }
  }
  return best;
}

/// Overall mostrato sulla carta: base più bonus, mai oltre 99.
int? overallWith(int? base, SpecialCard? card) =>
    base == null ? null : (base + (card?.bonus ?? 0)).clamp(40, 99);

/// Premio nero/oro da assegnare: giocatore, reparto e bonus.
class CardAward {
  const CardAward({
    required this.playerId,
    required this.reparto,
    this.bonus = 5,
  });
  final String playerId;
  final String reparto;
  final int bonus;

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'reparto': reparto,
    'bonus': bonus,
  };
}

abstract class SpecialCardsRepository {
  Stream<List<SpecialCard>> watchAll();

  /// Il Direttivo assegna le carte nero/oro della partita (sostituisce l'elenco
  /// precedente); restituisce quante carte nuove sono state date.
  Future<int> assign(ClubMatch match, List<CardAward> awards);
  Future<void> delete(String id);
  void dispose() {}
}

final specialCardsRepositoryProvider = Provider<SpecialCardsRepository>((ref) {
  final repo = AppConfig.isDemo
      ? DemoSpecialCardsRepository()
      : _SupabaseSpecialCardsRepository(ref);
  ref.onDispose(repo.dispose);
  return repo;
});

final specialCardsProvider = StreamProvider<List<SpecialCard>>(
  (ref) => ref.watch(specialCardsRepositoryProvider).watchAll(),
);

/// Carte valide adesso, per giocatore.
final activeSpecialCardsProvider = Provider<Map<String, SpecialCard>>((ref) {
  final cards = ref.watch(specialCardsProvider).value ?? const [];
  return activeSpecialCards(cards, ref.watch(clockProvider)());
});

/// La carta speciale valida adesso di un giocatore (null = carta normale).
final activeSpecialCardProvider = Provider.family<SpecialCard?, String>(
  (ref, playerId) => ref.watch(activeSpecialCardsProvider)[playerId],
);

class _SupabaseSpecialCardsRepository extends SpecialCardsRepository {
  _SupabaseSpecialCardsRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Stream<List<SpecialCard>> watchAll() => _client
      .from('special_cards')
      .stream(primaryKey: ['id'])
      .order('starts_at', ascending: false)
      .map((rows) => rows.map(SpecialCard.fromMap).toList());

  @override
  Future<int> assign(ClubMatch match, List<CardAward> awards) async {
    final n = await _client.rpc(
      'assign_special_cards',
      params: {
        'p_match': match.id,
        'p_awards': [for (final a in awards) a.toJson()],
      },
    );
    return (n as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('special_cards').delete().eq('id', id);
  }
}

/// Carte in memoria per la demo e i test.
class DemoSpecialCardsRepository extends SpecialCardsRepository {
  DemoSpecialCardsRepository() {
    final now = DateTime.now();
    SpecialCard card(
      String id,
      String player,
      CardSpecial kind,
      String reparto,
      int bonus, {
      required String match,
      required int daysAgo,
      String? reason,
    }) => SpecialCard(
      id: id,
      playerId: player,
      kind: kind,
      reparto: reparto,
      bonus: bonus,
      reason: reason ?? 'Carta della settimana',
      matchId: match,
      team: Team.milanac,
      startsAt: now.subtract(Duration(days: daysAgo)),
      endsAt: now.subtract(Duration(days: daysAgo - 7)),
      assignedBy: kind == CardSpecial.neroOro ? 'demo' : null,
    );
    _cards.addAll([
      // Questa settimana (dalla 2ª giornata): una nero/oro per reparto e la blu del portiere.
      card('sc1', 'p2', CardSpecial.neroOro, 'ATT', 5, match: 'm1', daysAgo: 2),
      card('sc2', 'p3', CardSpecial.neroOro, 'DIF', 4, match: 'm1', daysAgo: 2),
      card('sc3', 'demo', CardSpecial.neroOro, 'CEN', 5, match: 'm1', daysAgo: 2),
      card(
        'sc4',
        'p4',
        CardSpecial.blu,
        'POR',
        5,
        match: 'm1',
        daysAgo: 2,
        reason: 'Tre partite di fila senza subire gol',
      ),
      // La settimana scorsa (1ª giornata).
      card('sc5', 'p2', CardSpecial.neroOro, 'ATT', 5, match: 'm3', daysAgo: 11),
    ]);
  }

  final _cards = <SpecialCard>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 100;

  List<SpecialCard> get _sorted =>
      List.of(_cards)..sort((a, b) => b.startsAt.compareTo(a.startsAt));

  @override
  Stream<List<SpecialCard>> watchAll() async* {
    yield _sorted;
    yield* _changes.stream.map((_) => _sorted);
  }

  @override
  Future<int> assign(ClubMatch match, List<CardAward> awards) async {
    final keep = awards.map((a) => a.playerId).toSet();
    _cards.removeWhere(
      (c) =>
          c.matchId == match.id &&
          c.kind == CardSpecial.neroOro &&
          !keep.contains(c.playerId),
    );
    final now = DateTime.now();
    var added = 0;
    for (final a in awards) {
      bool same(SpecialCard c) =>
          c.matchId == match.id && c.playerId == a.playerId;
      // La blu elettrico ha la precedenza.
      if (_cards.any((c) => same(c) && c.isBlue)) continue;
      final i = _cards.indexWhere(
        (c) => same(c) && c.kind == CardSpecial.neroOro,
      );
      if (i >= 0) {
        _cards[i] = _cards[i].copyWith(bonus: a.bonus, reparto: a.reparto);
      } else {
        _cards.add(
          SpecialCard(
            id: 'sc${_next++}',
            playerId: a.playerId,
            kind: CardSpecial.neroOro,
            reparto: a.reparto,
            bonus: a.bonus,
            reason: 'Carta della settimana',
            matchId: match.id,
            team: match.team,
            startsAt: now,
            endsAt: now.add(const Duration(days: 7)),
            assignedBy: 'demo',
          ),
        );
        added++;
      }
    }
    _changes.add(null);
    return added;
  }

  @override
  Future<void> delete(String id) async {
    _cards.removeWhere((c) => c.id == id);
    _changes.add(null);
  }

  @override
  void dispose() => _changes.close();
}
