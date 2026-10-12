import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Il filo d'oro in cima alle schermate: la firma del tema nero oro.
class GoldRule extends StatelessWidget {
  const GoldRule({super.key, this.height = 3});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MilanacColors.goldDeep,
            MilanacColors.goldLight,
            MilanacColors.goldDeep,
          ],
        ),
      ),
    ),
  );
}

/// Etichetta di una sezione (maiuscolo, spaziata, grigia o oro).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.gold = false, this.trailing});
  final String text;
  final bool gold;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: gold ? context.pal.accentText : context.pal.textMuted,
      ),
    );
    if (trailing == null) return label;
    return Row(
      children: [
        Expanded(child: label),
        trailing!,
      ],
    );
  }
}

/// Card del tema: superficie con bordo sottile; [important] = bordo oro
/// (solo per ciò che conta oggi), [hero] = card in evidenza a fondo scuro caldo.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.important = false,
    this.hero = false,
    this.onTap,
    this.radius = 18,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool important;
  final bool hero;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color:
            borderColor ??
            (hero
                ? p.heroBorder
                : important
                ? p.importantBorder
                : p.border),
      ),
    );
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? (hero ? p.hero : p.surface),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Testo sopra una card "hero": sempre avorio, con l'oro per i numeri.
class HeroText {
  static const primary = MilanacColors.ivory;
  static const secondary = MilanacColors.ivoryMuted;
  static const accent = MilanacColors.goldLight;
}

/// Selettore a schede in stile nero oro (scheda attiva con la pillola dorata).
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.icons,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                label: labels[i],
                icon: icons?[i],
                selected: i == selected,
                onTap: () => onSelected(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = selected ? p.accentText : p.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.accentTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected ? p.accentTintBorder : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filtro a pillola (squadra, ruolo, categoria): selezionato con l'oro tenue.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.square = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(square ? 10 : 999);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.accentTint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? p.chipBorder : p.borderStrong),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // Larga quanto il testo anche dentro una Wrap.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? p.accentText : p.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pallino con un numero (messaggi non letti, cose da fare).
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: MilanacColors.gold,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: MilanacColors.ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Riquadro con icona per un'azione o una sezione (fondo oro tenue, icona oro).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 40, this.solid = false});
  final IconData icon;
  final double size;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? MilanacColors.gold : p.accentTint,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(
        icon,
        size: size * .55,
        color: solid ? MilanacColors.ink : p.accentText,
      ),
    );
  }
}
