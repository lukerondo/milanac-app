import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/ui.dart';
import '../carta/carta_page.dart';

/// Il tuo profilo (dalla foto in alto a destra): la carta, i dati e i traguardi,
/// con le impostazioni a un tocco.
class ProfiloPage extends StatelessWidget {
  const ProfiloPage({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
    // Aperto come unica pagina (dalla notifica delle carte speciali): indietro porta
    // alla Home invece di chiudere l'app.
    canPop: !(ModalRoute.of(context)?.isFirst ?? false),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.go('/');
    },
    child: Scaffold(
      appBar: AppBar(
        // Un solo blocco con la testata della carta (tavola 23).
        backgroundColor: context.pal.hero,
        leading: IconButton(
          tooltip: 'Indietro',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('IL TUO PROFILO'),
        actions: [
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/impostazioni'),
          ),
          const SizedBox(width: 4),
        ],
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
      ),
      body: const ContentWidth(child: MyCardPage()),
    ),
  );
}
