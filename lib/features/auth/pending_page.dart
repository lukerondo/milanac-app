import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';

/// Account bloccato o rimosso dal Direttivo: non si entra finché non viene riattivato.
/// Il profilo è ascoltato in tempo reale, quindi la pagina si sblocca da sola.
class PendingPage extends ConsumerWidget {
  const PendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    return StadiumBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/stemma_256.png', height: 96),
                    const SizedBox(height: 16),
                    Text(
                      profile == null
                          ? 'Account non attivo'
                          : 'Ciao ${profile.displayName}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: .4),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.block_rounded, color: Colors.redAccent),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Il tuo account è stato sospeso dal Direttivo. '
                              'Per informazioni contatta un membro del Direttivo.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
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
      ),
    );
  }
}
