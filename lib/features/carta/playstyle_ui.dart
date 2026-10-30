import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'archetypes.dart';
import 'card_colors.dart';

/// L'icona di un PlayStyle come sulle carte di FC: il PlayStyle+ in un rombo d'oro, il
/// PlayStyle normale in un tondo scuro bordato d'oro.
class PlayStyleBadge extends StatelessWidget {
  const PlayStyleBadge({
    super.key,
    required this.style,
    required this.plus,
    this.size = 26,
  });
  final PlayStyle style;
  final bool plus;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (plus)
          Transform.rotate(
            angle: .785398, // 45°: il rombo
            child: Container(
              width: size * .74,
              height: size * .74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * .12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CardColors.metalLight,
                    CardColors.metal,
                    CardColors.metalDeep,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: CardColors.metal.withValues(alpha: .5),
                    blurRadius: size * .25,
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MilanacColors.black.withValues(alpha: .55),
              border: Border.all(color: CardColors.metal, width: 1.2),
            ),
          ),
        Icon(
          style.icon,
          size: size * .5,
          color: plus ? MilanacColors.ink : CardColors.metalLight,
        ),
      ],
    ),
  );
}

/// Sotto la carta: l'archetipo (icona, nome e cosa fa) e i PlayStyle, i "+" in oro.
class ArchetypeCard extends StatelessWidget {
  const ArchetypeCard({
    super.key,
    required this.playStyle,
    required this.codes,
  });
  final String? playStyle;
  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final archetype = archetypeOf(playStyle);
    final style = playStyle?.trim() ?? '';
    final chosen = chosenPlayStyles(codes);
    if (style.isEmpty && chosen.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        hero: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (style.isNotEmpty) ...[
              const Text(
                'ARCHETIPO',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: HeroText.accent,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: MilanacColors.goldLight),
                      color: MilanacColors.black.withValues(alpha: .4),
                    ),
                    child: Icon(
                      archetype?.icon ?? Icons.sports_soccer_rounded,
                      color: MilanacColors.goldLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (archetype?.name ?? style).toUpperCase(),
                          style: const TextStyle(
                            fontFamily: sportFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .8,
                            color: HeroText.primary,
                          ),
                        ),
                        if (archetype != null)
                          Text(
                            archetype.description,
                            style: const TextStyle(
                              fontSize: 14,
                              color: HeroText.secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (chosen.isNotEmpty) ...[
              if (style.isNotEmpty) const SizedBox(height: 14),
              const Text(
                'PLAYSTYLE',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: HeroText.accent,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in chosen)
                    Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: c.plus
                            ? CardColors.metal.withValues(alpha: .18)
                            : MilanacColors.black.withValues(alpha: .35),
                        border: Border.all(
                          color: c.plus ? CardColors.metal : p.heroBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlayStyleBadge(style: c.style, plus: c.plus),
                          const SizedBox(width: 6),
                          Text(
                            c.plus ? '${c.style.name}+' : c.style.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.plus
                                  ? CardColors.metalLight
                                  : HeroText.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Scelta dei PlayStyle nell'editor della carta: un tocco lo aggiunge, il secondo lo
/// fa diventare PlayStyle+ (oro), il terzo lo toglie. Al massimo [maxPlayStyles], di
/// cui [maxPlayStylesPlus] "+": oltre lo dice.
class PlayStylePicker extends StatelessWidget {
  const PlayStylePicker({
    super.key,
    required this.codes,
    required this.onChanged,
  });
  final List<String> codes;
  final ValueChanged<List<String>> onChanged;

  int get _plus => codes.where((c) => c.endsWith('+')).length;

  void _cycle(BuildContext context, String code) {
    final next = [...codes];
    final i = next.indexWhere((c) => c == code || c == '$code+');
    String? warning;
    if (i < 0) {
      if (next.length >= maxPlayStyles) {
        warning = 'Al massimo $maxPlayStyles PlayStyle: togline uno prima.';
      } else {
        next.add(code);
      }
    } else if (!next[i].endsWith('+') && _plus < maxPlayStylesPlus) {
      next[i] = '$code+';
    } else {
      if (!next[i].endsWith('+')) {
        warning = 'Al massimo $maxPlayStylesPlus PlayStyle+: questo si toglie.';
      }
      next.removeAt(i);
    }
    if (warning != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(warning)));
    }
    Haptics.tap();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'PlayStyle',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '${codes.length}/$maxPlayStyles · '
              '$_plus/$maxPlayStylesPlus in oro',
              style: TextStyle(fontSize: 13, color: p.textMuted),
            ),
          ],
        ),
        Text(
          'Un tocco lo aggiunge, il secondo lo fa PlayStyle+ (oro), il terzo lo '
          'toglie.',
          style: TextStyle(fontSize: 13, color: p.textMuted),
        ),
        for (final group in PlayStyleGroup.values) ...[
          const SizedBox(height: 10),
          Text(
            group.label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: p.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in playStyleCatalog.where((s) => s.group == group))
                _PlayStyleChip(
                  style: s,
                  state: codes.contains('${s.code}+')
                      ? 2
                      : codes.contains(s.code)
                      ? 1
                      : 0,
                  onTap: () => _cycle(context, s.code),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Un PlayStyle da toccare: spento, scelto (bordo d'oro) o PlayStyle+ (pieno d'oro).
class _PlayStyleChip extends StatelessWidget {
  const _PlayStyleChip({
    required this.style,
    required this.state,
    required this.onTap,
  });
  final PlayStyle style;

  /// 0 spento, 1 PlayStyle, 2 PlayStyle+.
  final int state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (bg, border, fg) = switch (state) {
      2 => (CardColors.metal, CardColors.metal, MilanacColors.ink),
      1 => (p.accentTint, p.accentText, p.text),
      _ => (p.surface, p.border, p.textSecondary),
    };
    return Semantics(
      button: true,
      selected: state > 0,
      label: switch (state) {
        2 => '${style.name}, PlayStyle+',
        1 => '${style.name}, scelto',
        _ => style.name,
      },
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border, width: 1.4)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.icon, size: 18, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    state == 2 ? '${style.name}+' : style.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
