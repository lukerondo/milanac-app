import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/profile.dart';
import '../core/auth/providers.dart';
import '../core/teams.dart';
import '../core/theme.dart';
import '../features/chat/chat_list_page.dart';
import '../features/chat/chat_repository.dart';
import 'club_links.dart';
import 'club_links_editor.dart';
import 'sections.dart';

/// Nome del club nel menu: dipende dalla squadra del membro
/// (chi è solo in Milan AC Futuro vede il nome della sua squadra).
String clubTitleFor(Profile? profile) {
  final teams = profile?.teams ?? const {Team.milanac};
  return teams.contains(Team.milanac)
      ? 'MILAN AC PRO CLUB'
      : 'MILAN AC FUTURO PRO CLUB';
}

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final links = ref.watch(clubLinksProvider).value ?? const <ClubLink>[];
    final unread = ref.watch(chatUnreadProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [MilanacColors.redDark, MilanacColors.black],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/stemma_256.png',
                      height: 84,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    clubTitleFor(profile),
                    style: const TextStyle(
                      fontFamily: sportFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 19,
                      letterSpacing: 2,
                      color: MilanacColors.gold,
                    ),
                  ),
                  if (profile != null)
                    Text(
                      '${profile.displayName} · ${profile.roleLabel}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final s in appSections)
                    if (!s.direttivoOnly || (profile?.isDirettivo ?? false))
                      ListTile(
                        leading: Icon(s.icon),
                        title: Text(s.title),
                        trailing: s.path == '/chat' && unread > 0
                            ? UnreadBadge(unread)
                            : null,
                        selected: s.path == currentPath,
                        selectedColor: MilanacColors.gold,
                        selectedTileColor: MilanacColors.red.withValues(
                          alpha: 0.15,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(s.path);
                        },
                      ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final l in links)
                    IconButton(
                      tooltip: l.kind.label,
                      icon: Icon(l.kind.icon),
                      onPressed: () => launchUrl(
                        Uri.parse(l.url),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  if (profile?.isDirettivo ?? false)
                    IconButton(
                      tooltip: 'Modifica contatti',
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: MilanacColors.gold,
                      ),
                      onPressed: () {
                        final root = Navigator.of(context, rootNavigator: true);
                        Navigator.of(context).pop();
                        root.push(
                          MaterialPageRoute(
                            builder: (_) => ClubLinksEditorPage(initial: links),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
