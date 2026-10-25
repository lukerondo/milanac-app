import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Tiene tutta l'app sopra i tasti di sistema: la barra a 3 tasti dei Samsung,
/// la barra dei gesti di Android e l'indicatore Home dell'iPhone.
/// Vale per ogni pagina, pannello dal basso, finestra e bottone, anche quelli futuri.
/// Sotto i tasti resta una striscia del colore di sfondo; con la tastiera aperta sparisce.
class SystemBarsGuard extends StatelessWidget {
  const SystemBarsGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      systemNavigationBarColor: MilanacColors.black,
      systemNavigationBarDividerColor: MilanacColors.black,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
    child: ColoredBox(
      color: MilanacColors.black,
      child: SafeArea(top: false, child: child),
    ),
  );
}
