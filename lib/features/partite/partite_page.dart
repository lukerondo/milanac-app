import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ui.dart';
import '../calendario/calendario_page.dart';
import '../risultati/risultati_page.dart';
import '../tornei/tornei_page.dart';

/// Partite: Calendario, Risultati e Tornei nella stessa scheda.
///
/// La scheda scelta sta nella rotta (`/partite?scheda=risultati`): anche le schede in
/// alto cambiano la rotta. Così ogni collegamento e ogni notifica la seguono sempre,
/// anche quando portano alla stessa `?scheda=` di prima (es. "Tutti" degli ultimi
/// risultati toccato una seconda volta): una scelta tenuta solo nella pagina restava
/// indietro, perché il router non ricostruisce la pagina per una rotta uguale.
class PartitePage extends StatelessWidget {
  const PartitePage({super.key, this.tab});

  /// "calendario" (predefinita), "risultati" oppure "tornei".
  final String? tab;

  static const tabs = ['calendario', 'risultati', 'tornei'];

  static int indexOf(String? tab) {
    final i = tabs.indexOf(tab ?? '');
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final selected = indexOf(tab);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedTabs(
            labels: const ['Calendario', 'Risultati', 'Tornei'],
            selected: selected,
            onSelected: (i) {
              if (i != selected) context.go('/partite?scheda=${tabs[i]}');
            },
          ),
        ),
        // Solo la scheda scelta resta costruita (e collegata al server).
        Expanded(
          child: switch (selected) {
            1 => const RisultatiPage(),
            2 => const TorneiPage(),
            _ => const CalendarioPage(),
          },
        ),
      ],
    );
  }
}
