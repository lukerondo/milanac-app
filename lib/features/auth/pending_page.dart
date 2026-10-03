import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';

/// Mostrata finché il Direttivo non approva l'account.
/// Si sblocca da sola: il profilo è ascoltato in tempo reale.
class PendingPage extends ConsumerWidget {
  const PendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/stemma.png', height: 110),
                const SizedBox(height: 24),
                const Icon(Icons.hourglass_top_rounded, color: MilanacColors.gold, size: 40),
                const SizedBox(height: 12),
                Text('Account in attesa di approvazione',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Un membro del Direttivo deve approvare il tuo accesso. '
                  'Appena succede, l\'app si aprirà automaticamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Esci'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
