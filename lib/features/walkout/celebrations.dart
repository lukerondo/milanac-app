import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/local_flags.dart';
import '../carta/carta_page.dart';
import '../rosa/rosa_repository.dart';
import '../traguardi/achievements.dart';
import '../traguardi/achievements_view.dart';
import 'walkout_page.dart';

/// Chiave dell'ultimo overall per cui il giocatore ha visto il walkout su questo telefono.
String walkoutKey(String memberId) => 'walkout.overall.$memberId';

/// Fa partire, una volta sola per telefono:
/// - il walkout quando il giocatore entra nel club (prima apertura dopo l'approvazione)
///   o quando il suo overall sale (anche se lo alza il Direttivo, in tempo reale);
/// - la festa per i traguardi appena sbloccati.
/// In demo/test resta spento (il walkout si apre comunque dalla carta).
class Celebrations extends ConsumerStatefulWidget {
  const Celebrations({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<Celebrations> createState() => _CelebrationsState();
}

class _CelebrationsState extends ConsumerState<Celebrations> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (AppConfig.isDemo || _running || !mounted) return;
    final me = ref.read(profileProvider).value;
    if (me == null || !me.isApproved) return;
    final member = ref
        .read(rosaProvider)
        .value
        ?.where((m) => m.id == me.id)
        .firstOrNull;
    final stats = ref.read(cardStatsProvider(me.id));
    if (member == null || stats == null) return;

    _running = true;
    try {
      final flags = ref.read(localFlagsProvider);
      final key = walkoutKey(me.id);
      final seen = await flags.getString(key);
      final current = member.overall?.toString() ?? '-';
      final previous = seen == null ? null : int.tryParse(seen);
      if (seen == null) {
        await flags.setString(key, current);
        if (mounted) await showWalkout(context, member: member, stats: stats);
      } else if (member.overall != null && member.overall! > (previous ?? 0)) {
        await flags.setString(key, current);
        if (mounted) {
          await showWalkout(
            context,
            member: member,
            stats: stats,
            previousOverall: previous,
          );
        }
      } else if (seen != current) {
        await flags.setString(key, current);
      }

      final progress = ref.read(achievementsProvider(me.id));
      if (progress != null && mounted) {
        final seenKey = 'achievements.seen.${me.id}';
        final already = (await flags.getList(seenKey)).toSet();
        final fresh = [
          for (final p in progress)
            if (p.unlocked && !already.contains(p.achievement.id))
              p.achievement,
        ];
        if (fresh.isNotEmpty) {
          await flags.setList(seenKey, [
            ...already,
            for (final a in fresh) a.id,
          ]);
          if (mounted) await showUnlockCelebration(context, fresh);
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meId = ref.watch(profileProvider).value?.id;
    if (meId != null) {
      // Ricontrolla quando cambiano il profilo (overall) o i traguardi.
      ref.listen(rosaProvider, (_, _) => _check());
      ref.listen(achievementsProvider(meId), (_, _) => _check());
    }
    return widget.child;
  }
}
