import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';
import '../core/theme.dart';
import 'club_links.dart';
import 'club_links_editor.dart';
import 'sections.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final links = ref.watch(clubLinksProvider).value ?? const <ClubLink>[];

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
                    child: Image.asset('assets/images/stemma.png', height: 84),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MILANAC PRO CLUB',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.5,
                      color: MilanacColors.gold,
                    ),
                  ),
                  if (profile != null)
                    Text(
                      '${profile.displayName} · ${profile.isDirettivo ? 'Direttivo' : 'Giocatore'}',
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
                    ListTile(
                      leading: Icon(s.icon),
                      title: Text(s.title),
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
                  if (!AppConfig.isDemo)
                    ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Esci'),
                      onTap: () => ref.read(authRepositoryProvider).signOut(),
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
