import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';

/// Numeri di sempre di un giocatore per i traguardi (funzione `player_stats`).
class PlayerStats {
  const PlayerStats({
    this.presences = 0,
    this.late = 0,
    this.cleanMonth = false,
    this.neroOro = 0,
    this.blu = 0,
  });
  final int presences;
  final int late;

  /// Almeno un mese con 8 serate e nessun ritardo.
  final bool cleanMonth;

  /// Carte speciali ricevute: nero/oro della settimana e blu elettrico.
  final int neroOro;
  final int blu;

  factory PlayerStats.fromMap(Map<String, dynamic> m) => PlayerStats(
    presences: (m['presences'] as num?)?.toInt() ?? 0,
    late: (m['late'] as num?)?.toInt() ?? 0,
    cleanMonth: (m['clean_month'] as bool?) ?? false,
    neroOro: (m['nero_oro'] as num?)?.toInt() ?? 0,
    blu: (m['blu'] as num?)?.toInt() ?? 0,
  );
}

abstract class PlayerStatsRepository {
  Future<PlayerStats> load(String playerId);
}

final playerStatsRepositoryProvider = Provider<PlayerStatsRepository>((ref) {
  if (AppConfig.isDemo) return DemoPlayerStatsRepository();
  return _SupabasePlayerStatsRepository(ref);
});

final playerStatsProvider = FutureProvider.family<PlayerStats, String>(
  (ref, id) => ref.watch(playerStatsRepositoryProvider).load(id),
);

class _SupabasePlayerStatsRepository implements PlayerStatsRepository {
  _SupabasePlayerStatsRepository(this._ref);
  final Ref _ref;

  @override
  Future<PlayerStats> load(String playerId) async {
    final res = await _ref
        .read(supabaseProvider)
        .rpc('player_stats', params: {'p_player': playerId});
    return res is Map
        ? PlayerStats.fromMap(Map<String, dynamic>.from(res))
        : const PlayerStats();
  }
}

class DemoPlayerStatsRepository implements PlayerStatsRepository {
  @override
  Future<PlayerStats> load(String playerId) async => PlayerStats(
    presences: playerId == 'p2' ? 48 : 12,
    late: playerId == 'p3' ? 2 : 0,
    cleanMonth: playerId != 'p3',
    neroOro: switch (playerId) {
      'p2' => 2,
      'p3' || 'demo' => 1,
      _ => 0,
    },
    blu: playerId == 'p4' ? 1 : 0,
  );
}
