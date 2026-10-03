import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'achievements.dart';

/// Badge tondo: colore del livello se sbloccato, grigio con lucchetto se no.
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({
    super.key,
    required this.achievement,
    this.unlocked = true,
    this.size = 52,
  });
  final Achievement achievement;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? achievement.level.color : Colors.white24;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: unlocked ? .95 : .4),
            color.withValues(alpha: .25),
          ],
        ),
        border: Border.all(color: color, width: size / 22),
        boxShadow: unlocked
            ? [
                BoxShadow(
                  color: color.withValues(alpha: .45),
                  blurRadius: size / 4,
                ),
              ]
            : null,
      ),
      child: Icon(
        unlocked ? achievement.icon : Icons.lock_rounded,
        size: size * .5,
        color: unlocked ? Colors.white : Colors.white38,
      ),
    );
  }
}

/// Sezione "Traguardi" nella pagina della carta.
class AchievementsGrid extends ConsumerWidget {
  const AchievementsGrid({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(achievementsProvider(memberId));
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    final unlocked = list.where((p) => p.unlocked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(
            'TRAGUARDI  $unlocked/${list.length}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 8,
          childAspectRatio: .78,
          children: [
            for (final p in list)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _details(context, p),
                child: Column(
                  children: [
                    BadgeIcon(achievement: p.achievement, unlocked: p.unlocked),
                    const SizedBox(height: 6),
                    Text(
                      p.achievement.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.unlocked ? Colors.white : Colors.white54,
                      ),
                    ),
                    if (!p.unlocked) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: LinearProgressIndicator(
                          value: p.fraction,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        '${p.value.clamp(0, p.achievement.target)}/${p.achievement.target}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _details(
    BuildContext context,
    AchievementProgress p,
  ) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: BadgeIcon(
        achievement: p.achievement,
        unlocked: p.unlocked,
        size: 72,
      ),
      title: Text(p.achievement.title),
      content: Text(
        p.unlocked
            ? '${p.achievement.description}.\nSbloccato!'
            : '${p.achievement.description}.\n'
                  'Avanzamento: ${p.value.clamp(0, p.achievement.target)} su ${p.achievement.target}.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
      ],
    ),
  );
}

/// Festa per i traguardi appena sbloccati.
Future<void> showUnlockCelebration(
  BuildContext context,
  List<Achievement> unlocked,
) {
  HapticFeedback.heavyImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Chiudi',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (context, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unlocked.length == 1
                    ? 'TRAGUARDO SBLOCCATO!'
                    : '${unlocked.length} TRAGUARDI SBLOCCATI!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MilanacColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final a in unlocked)
                    SizedBox(
                      width: 110,
                      child: Column(
                        children: [
                          BadgeIcon(achievement: a, size: 84),
                          const SizedBox(height: 8),
                          Text(
                            a.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            a.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Grande!'),
              ),
            ],
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}
