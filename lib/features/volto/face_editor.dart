import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A0A0E), MilanacColors.surface],
            ),
            border: Border.all(color: MilanacColors.gold.withValues(alpha: .5)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: FaceView(face: face, size: previewSize),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: OutlinedButton.icon(
          onPressed: () {
            HapticFeedback.selectionClick();
            onChanged(Face.random());
          },
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
    final current = face.valueOf(part);
    final swatches = _swatches;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                part.label.toUpperCase(),
                style: const TextStyle(
                  fontFamily: sportFont,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  fontSize: 13,
                  color: MilanacColors.gold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                part.options[current],
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: swatches == null ? 38 : 40,
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

                if (swatches != null) {
                  return Semantics(
                    label: '${part.label}: ${part.options[i]}',
                    selected: selected,
                    button: true,
                    child: InkWell(
                      onTap: pick,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: swatches[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? MilanacColors.gold
                                : Colors.white24,
                            width: selected ? 3 : 1,
                          ),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  );
                }
                return ChoiceChip(
                  label: Text(part.options[i]),
                  selected: selected,
                  onSelected: (_) => pick(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
