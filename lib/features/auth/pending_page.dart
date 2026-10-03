import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';

/// Primo accesso: l'utente sceglie se entrare come Giocatore o Direttivo e attende
/// l'approvazione. Si sblocca da sola: il profilo è ascoltato in tempo reale.
class PendingPage extends ConsumerStatefulWidget {
  const PendingPage({super.key});

  @override
  ConsumerState<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends ConsumerState<PendingPage> {
  final _gamertag = TextEditingController();
  bool _saving = false;
  bool _gamertagLoaded = false;

  @override
  void dispose() {
    _gamertag.dispose();
    super.dispose();
  }

  Future<void> _save(ClubRole role) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .updateMyRequest(role: role, gamertag: _gamertag.text);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Richiesta inviata come ${role == ClubRole.direttivo ? 'Direttivo' : 'Giocatore'}.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Invio non riuscito: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (!_gamertagLoaded && profile != null) {
      _gamertag.text = profile.gamertag ?? '';
      _gamertagLoaded = true;
    }
    final requested = profile?.requestedRole ?? ClubRole.giocatore;
    final rejected = profile != null && !profile.active;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/stemma_milano_fc.png', height: 96),
                  const SizedBox(height: 16),
                  Text(
                    profile == null
                        ? 'Benvenuto!'
                        : 'Ciao ${profile.displayName.split(' ').first}!',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (rejected)
                    const _Notice(
                      icon: Icons.block_rounded,
                      color: Colors.redAccent,
                      text:
                          'La tua richiesta non è stata accettata. Per informazioni '
                          'contatta un membro del Direttivo.',
                    )
                  else ...[
                    const Text(
                      'Con quale ruolo vuoi entrare nel club?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _RoleCard(
                            icon: Icons.sports_soccer_rounded,
                            title: 'Giocatore',
                            subtitle: 'Gioco nella squadra',
                            selected: requested == ClubRole.giocatore,
                            onTap: _saving
                                ? null
                                : () => _save(ClubRole.giocatore),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoleCard(
                            icon: Icons.star_rounded,
                            title: 'Direttivo',
                            subtitle: 'Gestisco il club',
                            selected: requested == ClubRole.direttivo,
                            onTap: _saving
                                ? null
                                : () => _save(ClubRole.direttivo),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _gamertag,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(requested),
                      decoration: InputDecoration(
                        labelText: 'Il tuo gamertag (PSN / Xbox / EA ID)',
                        suffixIcon: IconButton(
                          tooltip: 'Salva',
                          icon: const Icon(Icons.check_rounded),
                          onPressed: _saving ? null : () => _save(requested),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _Notice(
                      icon: Icons.hourglass_top_rounded,
                      color: MilanacColors.gold,
                      text:
                          'Un membro del Direttivo deve approvare il tuo accesso. '
                          'Appena succede, l\'app si aprirà automaticamente.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => logout(ref),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Esci'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? MilanacColors.red.withValues(alpha: .2)
          : MilanacColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? MilanacColors.red : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: selected ? MilanacColors.gold : Colors.white70,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              if (selected) ...[
                const SizedBox(height: 6),
                const Icon(
                  Icons.check_circle_rounded,
                  color: MilanacColors.red,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .4)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}
