import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui.dart';

/// Le pagine a schermo intero di lavagna, replay e schemi: barra in alto con la
/// freccia indietro, il titolo e il filo d'oro in cima.
AppBar fullPageBar(
  BuildContext context, {
  required String title,
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
  VoidCallback? onBack,
}) => AppBar(
  automaticallyImplyLeading: false,
  leading: IconButton(
    tooltip: 'Indietro',
    icon: const Icon(Icons.arrow_back_rounded),
    // maybePop: rispetta le conferme (registrazione in corso, replay non inviato).
    onPressed: onBack ?? () => Navigator.maybePop(context),
  ),
  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
  actions: actions,
  bottom: bottom ?? const _BarLine(),
  flexibleSpace: const Align(alignment: Alignment.topCenter, child: GoldRule()),
);

/// Il filo sottile sotto la barra in alto.
class _BarLine extends StatelessWidget implements PreferredSizeWidget {
  const _BarLine();

  @override
  Size get preferredSize => const Size.fromHeight(1);

  @override
  Widget build(BuildContext context) => AlwaysDark(
    child: Builder(
      builder: (context) => ColoredBox(
        color: context.pal.border,
        child: const SizedBox(height: 1, width: double.infinity),
      ),
    ),
  );
}

/// Il pulsante di una conferma che non si può annullare (eliminare, buttare il
/// replay): rosso del tema invece dell'oro.
ButtonStyle dangerButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: scheme.error,
    foregroundColor: scheme.onError,
  );
}

/// Il tema scuro per le parti sempre scure, anche quando l'app è nel tema chiaro.
final _darkTheme = buildTheme(Brightness.dark);

/// Una parte sempre scura (la barra in alto con modulo e squadra, gli strumenti in
/// basso): dentro, `context.pal` dà i colori del tema scuro.
class AlwaysDark extends StatelessWidget {
  const AlwaysDark({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: _darkTheme, child: child);
}
