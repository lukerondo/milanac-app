import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/providers.dart';
import '../core/theme.dart';
import '../features/chat/chat_repository.dart';
import '../features/rosa/rosa_repository.dart';
import 'app_shell.dart' show clubTitleFor;
import 'member_photo.dart';
import 'sections.dart';
import 'ui.dart';

/// Menu laterale degli schermi larghi: prende il posto della barra in basso. In alto
/// lo stemma e il nome del club, poi le cinque schede (quella aperta in oro, con i
/// messaggi non letti sulla Chat) e in fondo la tua foto, che apre il profilo, con le
/// impostazioni accanto. Sempre scuro, come la barra in basso e quella in alto.
class SideMenu extends ConsumerWidget {
  const SideMenu({super.key, required this.current, required this.onSelect});

  /// La scheda aperta.
  final MainTab current;
  final ValueChanged<MainTab> onSelect;

  static const width = 232.0;

  /// Testi e icone delle voci non scelte (come nella barra in basso).
  static const _muted = Color(0xFFA8A29A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(chatUnreadProvider);
    final profile = ref.watch(profileProvider).value;
    // "MILANAC PRO CLUB" su due righe: il nome della squadra e "PRO CLUB".
    final team = clubTitleFor(profile).replaceFirst(' PRO CLUB', '');
    return SizedBox(
      width: width,
      child: Material(
        color: MilanacColors.surface,
        shape: Border(right: BorderSide(color: AppPalette.dark.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GoldRule(),
            Expanded(
              child: SafeArea(
                right: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/images/stemma_256.png',
                            width: 42,
                            height: 42,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  team,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: sportFont,
                                    fontSize: 19,
                                    height: 1.1,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                    color: MilanacColors.ivory,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'PRO CLUB',
                                  style: TextStyle(
                                    fontFamily: sportFont,
                                    fontSize: 12,
                                    height: 1.1,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 2.4,
                                    color: MilanacColors.goldLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          for (final t in MainTab.values)
                            _MenuItem(
                              tab: t,
                              selected: t == current,
                              unread: t == MainTab.chat ? unread : 0,
                              onTap: () => onSelect(t),
                            ),
                        ],
                      ),
                    ),
                    ColoredBox(
                      color: AppPalette.dark.border,
                      child: const SizedBox(height: 1),
                    ),
                    const _ProfileRow(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una voce del menu: icona e nome; quella aperta ha la pillola dorata.
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.tab,
    required this.selected,
    required this.unread,
    required this.onTap,
  });
  final MainTab tab;
  final bool selected;

  /// Messaggi non letti (solo sulla Chat).
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppPalette.dark.accentTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: selected
              ? BorderSide(color: AppPalette.dark.accentTintBorder)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0x14F5F1E6),
          child: Semantics(
            button: true,
            selected: selected,
            child: SizedBox(
              height: 46,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    selected ? tab.selectedIcon : tab.icon,
                    size: 22,
                    color: selected ? MilanacColors.goldLight : SideMenu._muted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 15.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? MilanacColors.ivory : SideMenu._muted,
                      ),
                    ),
                  ),
                  if (unread > 0) ...[
                    Badge(
                      largeSize: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: const TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      label: Text(unread > 99 ? '99+' : '$unread'),
                    ),
                    const SizedBox(width: 14),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return unread > 0
        ? Tooltip(message: '${tab.label}, $unread messaggi nuovi', child: item)
        : item;
  }
}

/// In fondo al menu: la tua foto e il tuo nome (aprono il profilo con la carta) e,
/// accanto, le impostazioni.
class _ProfileRow extends ConsumerWidget {
  const _ProfileRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final member = me == null
        ? null
        : ref
              .watch(rosaProvider)
              .value
              ?.where((m) => m.id == me.id)
              .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Il tuo profilo',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                hoverColor: const Color(0x14F5F1E6),
                onTap: () => context.push('/profilo'),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFB8952F),
                        ),
                        child: member == null
                            ? const CircleAvatar(
                                radius: 17,
                                backgroundColor: MilanacColors.surfaceHigh,
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 20,
                                  color: MilanacColors.ivoryMuted,
                                ),
                              )
                            : MemberAvatar(member: member, radius: 17),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me?.displayName ?? 'Profilo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: bodyFont,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: MilanacColors.ivory,
                              ),
                            ),
                            const Text(
                              'Profilo e carta',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: bodyFont,
                                fontSize: 12.5,
                                color: SideMenu._muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_outlined, size: 22),
            color: SideMenu._muted,
            onPressed: () => context.push('/impostazioni'),
          ),
        ],
      ),
    );
  }
}
