import 'package:flutter/material.dart';

import '../../shared/ui.dart';
import '../calendario/calendario_page.dart';
import '../risultati/risultati_page.dart';
import '../tornei/tornei_page.dart';

/// Partite: Calendario, Risultati e Tornei nella stessa scheda.
class PartitePage extends StatefulWidget {
  const PartitePage({super.key, this.initialTab});

  /// "calendario" (predefinita), "risultati" oppure "tornei".
  final String? initialTab;

  static const tabs = ['calendario', 'risultati', 'tornei'];

  @override
  State<PartitePage> createState() => _PartitePageState();
}

class _PartitePageState extends State<PartitePage> {
  late int _tab = _indexOf(widget.initialTab);

  static int _indexOf(String? tab) {
    final i = PartitePage.tabs.indexOf(tab ?? '');
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant PartitePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stessa pagina, rotta cambiata (es. "Tornei" dal Club o da una notifica).
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      setState(() => _tab = _indexOf(widget.initialTab));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SegmentedTabs(
          labels: const ['Calendario', 'Risultati', 'Tornei'],
          selected: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
      ),
      // Solo la scheda scelta resta costruita (e collegata al server).
      Expanded(
        child: switch (_tab) {
          1 => const RisultatiPage(),
          2 => const TorneiPage(),
          _ => const CalendarioPage(),
        },
      ),
    ],
  );
}
