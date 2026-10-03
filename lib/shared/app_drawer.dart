import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/providers.dart';
import '../core/push/device_tokens.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../features/chat/chat_list_page.dart';
import '../features/chat/chat_repository.dart';
import '../features/privacy/privacy_page.dart';
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
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy'),
                    onTap: () {
                      final root = Navigator.of(context, rootNavigator: true);
                      Navigator.of(context).pop();
                      root.push(
                        MaterialPageRoute(builder: (_) => const PrivacyPage()),
                      );
                    },
                  ),
                  if (!AppConfig.isDemo) ...[
                    ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Esci'),
                      onTap: () => logout(ref),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.person_off_outlined,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        'Elimina il mio account',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () => _confirmDeleteAccount(context, ref),
                    ),
                  ],
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

Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Eliminare il tuo account?'),
      content: const Text(
        'Verranno cancellati definitivamente il tuo account, il profilo e lo storico delle '
        'presenze. Per rientrare nel club dovrai essere approvato di nuovo dal Direttivo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Elimina'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(authRepositoryProvider).deleteAccount();
    messenger.showSnackBar(const SnackBar(content: Text('Account eliminato.')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Eliminazione non riuscita: $e')),
    );
  }
}
