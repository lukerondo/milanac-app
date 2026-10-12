import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../auth/gate_ui.dart';
import 'face.dart';
import 'face_view.dart';

/// Creatore del volto: anteprima grande, pulsante "A caso" e una riga di scelte per parte.
class FaceEditor extends StatelessWidget {
  const FaceEditor({
    super.key,
    required this.face,
    required this.onChanged,
    this.previewSize = 180,
  });

  final Face face;
  final ValueChanged<Face> onChanged;
  final double previewSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // L'anteprima sta su un fondo sempre scuro (come la carta), in entrambi i temi.
        Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: p.hero,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.importantBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FaceView(face: face, size: previewSize),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged(Face.random());
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.casino_rounded),
            label: const Text('A caso'),
          ),
        ),
        const SizedBox(height: 8),
        for (final part in FacePart.values)
          _PartRow(part: part, face: face, onChanged: onChanged),
      ],
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.part,
    required this.face,
    required this.onChanged,
  });
  final FacePart part;
  final Face face;
  final ValueChanged<Face> onChanged;

  List<Color>? get _swatches => switch (part) {
    FacePart.skin => faceSkinColors,
    FacePart.hairColor => faceHairColors,
    FacePart.eyeColor => faceEyeColors,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final current = face.valueOf(part);
    final swatches = _swatches;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                part.label.toUpperCase(),
                style: TextStyle(
                  fontFamily: sportFont,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  fontSize: 13,
                  color: p.accentText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  part.options[current],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textMuted, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: part.count,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == current;
                void pick() {
                  HapticFeedback.selectionClick();
                  onChanged(face.withPart(part, i));
                }

                if (swatches == null) {
                  return ChoicePill(
                    label: part.options[i],
                    selected: selected,
                    onTap: pick,
                  );
                }
                final swatch = swatches[i];
                return Semantics(
                  label: '${part.label}: ${part.options[i]}',
                  selected: selected,
                  button: true,
                  child: InkWell(
                    onTap: pick,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? p.accentText : p.borderStrong,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              Icons.check_rounded,
                              size: 20,
                              // Il segno si legge sul colore del campione, non sul tema.
                              color: swatch.computeLuminance() > .45
                                  ? MilanacColors.ink
                                  : MilanacColors.ivory,
                            )
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
