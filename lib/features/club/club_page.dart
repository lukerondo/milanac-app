import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/club_links.dart';
import '../../shared/club_links_editor.dart';
import '../../shared/sections.dart';
import '../../shared/ui.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

/// Il Club: tutte le sezioni del club a un tocco, i Tornei (che stanno in Partite),
/// la Sala Direttivo per chi ne fa parte e i contatti social.
class ClubPage extends ConsumerWidget {
  const ClubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final me = ref.watch(profileProvider).value;
    final members = ref.watch(rosaProvider).value ?? const <Member>[];
    final count = members
        .where((m) => m.active && m.role != ClubRole.pending)
        .length;
    final links = ref.watch(clubLinksProvider);
    final isDirettivo = me?.isDirettivo ?? false;

    Widget entry({
      required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
    }) => AppCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconTile(icon),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textMuted, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AppCard(
          hero: true,
          child: Row(
            children: [
              Image.asset('assets/images/stemma_256.png', height: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clubTitleFor(me),
                      style: const TextStyle(
                        fontFamily: sportFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                        letterSpacing: 1.2,
                        color: HeroText.accent,
                      ),
                    ),
                    Text(
                      count == 0
                          ? 'Fondato a settembre 2025'
                          : 'Fondato a settembre 2025 · $count tesserati',
                      style: const TextStyle(
                        color: HeroText.secondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width > 560 ? 3 : 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // Altezza fissa che cresce con la dimensione del testo scelta sul telefono.
            mainAxisExtent: 72 + MediaQuery.textScalerOf(context).scale(40),
          ),
          children: [
            for (final s in clubSections)
              entry(
                title: s.title,
                subtitle: s.subtitle ?? '',
                icon: s.icon,
                onTap: () => context.push(s.path),
              ),
            entry(
              title: 'Tornei',
              subtitle: 'Anche in Partite',
              icon: Icons.leaderboard_rounded,
              onTap: () => context.go('/partite?scheda=tornei'),
            ),
          ],
        ),
        if (isDirettivo) ...[
          const SizedBox(height: 14),
          Material(
            color: MilanacColors.gold,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/direttivo'),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: MilanacColors.ink,
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          color: MilanacColors.goldLight,
                        ),
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sala Direttivo',
                            style: TextStyle(
                              color: MilanacColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Solo per il Direttivo',
                            style: TextStyle(
                              color: Color(0xFF3A2E0A),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: MilanacColors.ink),
                  ],
                ),
              ),
            ),
          ),
        ],
        if ((links.value?.isNotEmpty ?? false) || isDirettivo) ...[
          const SizedBox(height: 22),
          SectionLabel(
            'Seguici',
            trailing: isDirettivo && links.hasValue
                ? IconButton(
                    tooltip: 'Modifica contatti',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit_rounded, color: p.accentText),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubLinksEditorPage(
                              initial: links.requireValue,
                            ),
                          ),
                        ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in links.value ?? const <ClubLink>[])
                ActionChip(
                  avatar: Icon(l.kind.icon, size: 18, color: p.accentText),
                  label: Text(l.kind.label),
                  onPressed: () => _open(context, l.url),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const AppError('Link non apribile');
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Link non apribile'))),
      );
    }
  }
}
