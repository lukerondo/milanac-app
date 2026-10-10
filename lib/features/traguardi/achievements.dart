import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../carta/card_stats.dart';
import '../carta/carta_page.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'player_stats.dart';

/// Livello del badge (colore), dal più comune al più raro.
enum BadgeLevel {
  bronzo(Color(0xFFD9A273)),
  argento(Color(0xFFC9CED6)),
  oro(MilanacColors.gold),
  leggenda(MilanacColors.red);

  const BadgeLevel(this.color);
  final Color color;
}

/// I numeri da cui dipendono i traguardi.
class AchievementInput {
  const AchievementInput({
    required this.stats,
    required this.goals,
    required this.months,
    required this.overall,
  });
  final PlayerStats stats;
  final int goals;
  final int months;
  final int? overall;
}

class Achievement {
  const Achievement(
    this.id,
    this.title,
    this.description,
    this.icon,
    this.level,
    this.target,
    this.progressOf,
  );
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final BadgeLevel level;
  final int target;
  final int Function(AchievementInput) progressOf;
}

/// Catalogo dei traguardi, dal più facile al più raro.
final achievements = <Achievement>[
  Achievement(
    'presenze_10',
    'Presenza fissa',
    '10 serate con il club',
    Icons.how_to_reg_rounded,
    BadgeLevel.bronzo,
    10,
    (i) => i.stats.presences,
  ),
  Achievement(
    'gol_1',
    'Primo gol',
    'Il primo gol con la maglia del club',
    Icons.sports_soccer_rounded,
    BadgeLevel.bronzo,
    1,
    (i) => i.goals,
  ),
  Achievement(
    'svizzero',
    'Svizzero',
    'Un mese intero (almeno 8 serate) senza ritardi',
    Icons.schedule_rounded,
    BadgeLevel.argento,
    1,
    (i) => i.stats.cleanMonth ? 1 : 0,
  ),
  Achievement(
    'presenze_50',
    'Colonna del club',
    '50 serate con il club',
    Icons.groups_rounded,
    BadgeLevel.argento,
    50,
    (i) => i.stats.presences,
  ),
  Achievement(
    'gol_10',
    'Bomber',
    '10 gol segnati',
    Icons.local_fire_department_rounded,
    BadgeLevel.oro,
    10,
    (i) => i.goals,
  ),
  Achievement(
    'carta_settimana',
    'Carta della settimana',
    'Premiato dal Direttivo con la carta nero/oro',
    Icons.military_tech_rounded,
    BadgeLevel.oro,
    1,
    (i) => i.stats.neroOro,
  ),
  Achievement(
    'anni_1',
    'Bandiera',
    'Un anno nel club',
    Icons.flag_rounded,
    BadgeLevel.oro,
    12,
    (i) => i.months,
  ),
  Achievement(
    'presenze_100',
    'Leggenda della lobby',
    '100 serate con il club',
    Icons.stadium_rounded,
    BadgeLevel.leggenda,
    100,
    (i) => i.stats.presences,
  ),
  Achievement(
    'gol_25',
    'Capocannoniere',
    '25 gol segnati',
    Icons.whatshot_rounded,
    BadgeLevel.leggenda,
    25,
    (i) => i.goals,
  ),
  Achievement(
    'blu_elettrico',
    'Blu elettrico',
    'Tripletta, o tre partite ufficiali di fila senza subire gol',
    Icons.bolt_rounded,
    BadgeLevel.leggenda,
    1,
    (i) => i.stats.blu,
  ),
  Achievement(
    'fuoriclasse',
    'Fuoriclasse',
    'Carta rossonera: overall 85 o più',
    Icons.auto_awesome_rounded,
    BadgeLevel.leggenda,
    85,
    (i) => i.overall ?? 0,
  ),
];

/// Un traguardo con l'avanzamento del giocatore.
class AchievementProgress {
  const AchievementProgress(this.achievement, this.value);
  final Achievement achievement;
  final int value;

  bool get unlocked => value >= achievement.target;
  double get fraction => (value / achievement.target).clamp(0, 1);
}

/// Traguardi di un membro (null finché i dati non sono pronti).
final achievementsProvider =
    Provider.family<List<AchievementProgress>?, String>((ref, memberId) {
      final member = ref
          .watch(rosaProvider)
          .value
          ?.where((m) => m.id == memberId)
          .firstOrNull;
      final card = ref.watch(cardStatsProvider(memberId));
      final stats = ref.watch(playerStatsProvider(memberId)).value;
      if (member == null || card == null || stats == null) return null;
      return progressFor(member, card, stats);
    });

List<AchievementProgress> progressFor(
  Member member,
  CardStats card,
  PlayerStats stats,
) {
  final input = AchievementInput(
    stats: stats,
    goals: card.goals,
    months: card.months,
    overall: member.overall,
  );
  return [
    for (final a in achievements) AchievementProgress(a, a.progressOf(input)),
  ];
}

/// I badge più rari sbloccati (per la carta).
List<Achievement> topBadges(List<AchievementProgress> list, {int max = 3}) {
  final unlocked =
      list.where((p) => p.unlocked).map((p) => p.achievement).toList()
        ..sort((a, b) => b.level.index.compareTo(a.level.index));
  return unlocked.take(max).toList();
}
