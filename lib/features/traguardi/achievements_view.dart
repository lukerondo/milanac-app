import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../carta/card_colors.dart';
import 'achievements.dart';

/// Badge tondo di un traguardo: metallo del livello (i leggendari neri e oro), o
/// grigio con il lucchetto se non è ancora sbloccato.
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
    final p = context.pal;
    if (!unlocked) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.surfaceHigh,
          border: Border.all(color: p.borderStrong, width: size / 26),
        ),
        child: Icon(
          Icons.lock_rounded,
          size: size * .45,
          color: p.textDisabled,
        ),
      );
    }
    final level = achievement.level;
    final legend = level == BadgeLevel.leggenda;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: legend
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [CardColors.neroOroLight, CardColors.neroOro],
              )
            : RadialGradient(
                colors: [
                  level.color,
                  Color.lerp(level.color, MilanacColors.black, .3)!,
                ],
              ),
        border: Border.all(
          color: legend ? CardColors.gold : level.color,
          width: size / 22,
        ),
        boxShadow: [
          BoxShadow(
            color: level.color.withValues(alpha: .35),
            blurRadius: size / 4,
          ),
        ],
      ),
      child: Icon(
        achievement.icon,
        size: size * .5,
        color: legend ? CardColors.goldText : MilanacColors.ink,
      ),
    );
  }
}

/// Altezza delle tessere dei traguardi (cresce con il testo grande del telefono).
double _tileHeight(BuildContext context) =>
    60 + 52 * MediaQuery.textScalerOf(context).scale(1);

/// Sezione "Traguardi" del profilo: "TRAGUARDI · N DI 11" e le tessere, nere e oro
/// quelle sbloccate (come le carte), con il lucchetto le altre.
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
        Text(
          'TRAGUARDI · $unlocked DI ${list.length}',
          style: const TextStyle(
            fontFamily: sportFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: .9,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: _tileHeight(context),
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => _AchievementTile(progress: list[i]),
        ),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.progress});
  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final a = progress.achievement;
    final on = progress.unlocked;
    final target = a.target;
    return Material(
      color: on ? CardColors.neroOro : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? CardColors.gold : p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _details(context, progress),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Icon(
                on ? a.icon : Icons.lock_rounded,
                size: 28,
                color: on ? CardColors.goldText : p.textDisabled,
              ),
              const SizedBox(height: 6),
              Text(
                a.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: on ? CardColors.goldText : p.text,
                ),
              ),
              if (!on) ...[
                const SizedBox(height: 4),
                Text(
                  target > 1
                      ? '${progress.value.clamp(0, target)}/$target'
                      : 'Da sbloccare',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _details(BuildContext context, AchievementProgress p) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    icon: BadgeIcon(achievement: p.achievement, unlocked: p.unlocked, size: 72),
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

/// Festa per i traguardi appena sbloccati (sopra un velo scuro, uguale nei due temi).
Future<void> showUnlockCelebration(
  BuildContext context,
  List<Achievement> unlocked,
) {
  HapticFeedback.heavyImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Chiudi',
    barrierColor: MilanacColors.black.withValues(alpha: .9),
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
                  fontFamily: sportFont,
                  color: MilanacColors.goldLight,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: MilanacColors.ivory,
                            ),
                          ),
                          Text(
                            a.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: MilanacColors.ivoryMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                // Il velo è sempre scuro: l'oro pieno anche nel tema chiaro.
                style: FilledButton.styleFrom(
                  backgroundColor: MilanacColors.gold,
                  foregroundColor: MilanacColors.ink,
                ),
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
