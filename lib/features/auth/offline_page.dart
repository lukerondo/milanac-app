import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';

/// Profilo non caricato (telefono offline, server irraggiungibile): non è un nuovo membro
/// da mandare alla registrazione. Si riprova da qui; appena il profilo arriva (anche con i
/// nuovi tentativi automatici) il router prosegue da solo.
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(profileProvider).error;
    return StadiumBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('NESSUNA CONNESSIONE'),
          automaticallyImplyLeading: false,
          actions: [
            if (!AppConfig.isDemo)
              IconButton(
                tooltip: 'Esci',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => logout(ref),
              ),
          ],
        ),
        body: ErrorRetry(
          message: error == null
              ? 'Nessuna connessione: controlla la rete e riprova.'
              : friendlyError(
                  error,
                  action: 'Caricamento del profilo non riuscito',
                ),
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }
}
