import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/providers.dart';
import '../core/errors.dart';
import '../core/push/device_tokens.dart';
import '../core/theme.dart';
import '../features/regolamento/rules_repository.dart';
import 'ui.dart';

/// Il profilo non si carica (niente rete, server irraggiungibile): invece di
/// mandare alla registrazione, l'app aspetta qui e riprova da sola. Appena il
/// profilo arriva, il router riporta dove si voleva andare.
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final p = context.pal;
    final error = profile.error;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const GoldRule(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/stemma_256.png', height: 96),
                      const SizedBox(height: 24),
                      Text(
                        'NESSUNA CONNESSIONE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: sportFont,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: p.accentText,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        error == null || isNetworkError(error)
                            ? 'Non riusciamo a raggiungere il club. Controlla la rete: '
                                  'riproviamo da soli appena torna.'
                            : friendlyError(
                                error,
                                action: 'Il tuo profilo non si carica',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (profile.retrying)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Riprovo…',
                            style: TextStyle(color: p.textMuted),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: () {
                          ref.invalidate(profileProvider);
                          ref.invalidate(latestRulesProvider);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Riprova adesso'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => logout(ref),
                        child: const Text('Esci dall\'account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
