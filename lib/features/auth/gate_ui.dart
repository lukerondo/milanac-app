import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/ui.dart';

/// Pezzi comuni delle pagine a schermo intero di accesso, registrazione, regolamento
/// e impostazioni (tavole 02, 03, 04, 25).

/// Barra in alto con il filo d'oro in cima e il titolo in Oswald.
AppBar gateAppBar({
  required String title,
  Widget? leading,
  double? leadingWidth,
  bool automaticallyImplyLeading = true,
  List<Widget> actions = const [],
  bool divider = false,
}) => AppBar(
  leading: leading,
  leadingWidth: leadingWidth,
  automaticallyImplyLeading: automaticallyImplyLeading,
  title: Text(title),
  actions: [...actions, if (actions.isNotEmpty) const SizedBox(width: 4)],
  flexibleSpace: const Align(alignment: Alignment.topCenter, child: GoldRule()),
  // La barra è sempre scura: il filo sotto usa il bordo del tema scuro.
  bottom: divider
      ? PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: ColoredBox(
            color: AppPalette.dark.border,
            child: const SizedBox(height: 1, width: double.infinity),
          ),
        )
      : null,
);

/// Freccia indietro della barra in alto.
class BackArrow extends StatelessWidget {
  const BackArrow({
    super.key,
    required this.onPressed,
    this.tooltip = 'Indietro',
  });
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.arrow_back_rounded),
    onPressed: onPressed,
  );
}

/// Campo con l'etichetta sopra (come nelle tavole), ed eventuale nota sotto.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.help,
  });
  final String label;
  final Widget child;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          child,
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help!, style: TextStyle(fontSize: 13, color: p.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// "Mostra" / "Nascondi" dentro il campo della password.
class ShowPasswordButton extends StatelessWidget {
  const ShowPasswordButton({
    super.key,
    required this.hidden,
    required this.onPressed,
  });
  final bool hidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: context.pal.textMuted,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    child: Text(hidden ? 'Mostra' : 'Nascondi'),
  );
}

/// Titolo di una pagina o di un passo (Oswald maiuscolo).
class GateTitle extends StatelessWidget {
  const GateTitle(this.text, {super.key, this.size = 18, this.gold = false});
  final String text;
  final double size;
  final bool gold;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: sportFont,
      fontWeight: FontWeight.w600,
      fontSize: size,
      letterSpacing: size >= 24 ? 1 : .6,
      color: gold ? context.pal.accentText : context.pal.text,
    ),
  );
}

/// Pulsante dell'azione principale: oro pieno, alto 52.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.fontSize = 17,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: TextStyle(
          fontFamily: bodyFont,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
      child: busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: p.textDisabled,
              ),
            )
          // Un'etichetta lunga si stringe un poco invece di andare a capo.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(label, maxLines: 1),
                ],
              ),
            ),
    );
  }
}

/// Scelta a pillola alta 44 (piattaforma, ruoli nel Direttivo, piede): selezionata
/// con l'oro tenue.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(999);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.accentTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? p.chipBorder : p.borderStrong,
            width: selected ? 1 : 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? p.accentText : p.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fascia in basso con le azioni del passo (fondo superficie, filo sopra).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: child,
        ),
      ),
    );
  }
}

/// Fascia sotto la barra in alto (passi, versione, selettore): fondo superficie e
/// filo in basso.
class SubHeader extends StatelessWidget {
  const SubHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 12),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
