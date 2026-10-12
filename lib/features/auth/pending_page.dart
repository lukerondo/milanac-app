import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'gate_ui.dart';

/// Account rimosso o sospeso dal Direttivo: non si entra finché non viene riattivato
/// (Sala Direttivo → Rosa e squadre → Rimossi → Riattiva). Il profilo è ascoltato in
/// tempo reale, quindi la pagina si sblocca da sola.
class PendingPage extends ConsumerWidget {
  const PendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const GoldRule(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/images/stemma_256.png',
                            height: 96,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: GateTitle(
                            profile == null
                                ? 'Account non attivo'
                                : 'Ciao ${profile.displayName}',
                            size: 24,
                            gold: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: p.dangerBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.block_rounded, color: p.danger),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Il tuo account è stato rimosso o sospeso dal '
                                  'Direttivo. Chiedi a un membro del Direttivo di '
                                  'riattivarlo da Rosa e squadre: appena lo fa, '
                                  'questa pagina si sblocca da sola.',
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: () => logout(ref),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Esci'),
                        ),
                      ],
                    ),
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
