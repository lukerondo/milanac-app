import 'package:flutter/material.dart';

/// Da questa larghezza (in punti logici) l'app si dispone come su un computer: menu
/// laterale al posto della barra in basso e chat a due colonne. Sotto resta tutto
/// com'è sui telefoni.
const wideLayoutMinWidth = 1000.0;

/// Lo schermo (o la finestra del browser) è abbastanza largo per il layout da PC.
/// Chi lo chiede viene ridisegnato quando la finestra cambia dimensione.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

/// Come [isWideLayout], ma senza legarsi ai cambi di dimensione: per le scelte che si
/// fanno una volta sola (per esempio come si apre una pagina).
bool isWideLayoutNow(BuildContext context) =>
    MediaQueryData.fromView(View.of(context)).size.width >= wideLayoutMinWidth;

/// Sugli schermi larghi gli avvisi in basso (SnackBar) restano una striscia al centro,
/// non larga quanto tutta la finestra. Va messo sopra lo `Scaffold` della pagina; sotto
/// la soglia non cambia nulla.
class WideSnackBars extends StatelessWidget {
  const WideSnackBars({super.key, required this.child});
  final Widget child;

  /// Larghezza degli avvisi sugli schermi larghi.
  static const width = 520.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: isWideLayout(context)
          ? theme.copyWith(
              snackBarTheme: theme.snackBarTheme.copyWith(width: width),
            )
          : theme,
      child: child,
    );
  }
}
