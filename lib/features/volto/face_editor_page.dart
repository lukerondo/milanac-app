import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../auth/gate_ui.dart';
import 'face.dart';
import 'face_editor.dart';

/// Pagina a schermo intero per cambiare il volto; restituisce il nuovo [Face].
class FaceEditorPage extends StatefulWidget {
  const FaceEditorPage({super.key, required this.initial});
  final Face initial;

  @override
  State<FaceEditorPage> createState() => _FaceEditorPageState();
}

class _FaceEditorPageState extends State<FaceEditorPage> {
  late Face _face = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: gateAppBar(
      title: 'IL TUO VOLTO',
      divider: true,
      actions: [
        // La barra in alto è sempre scura: l'azione resta in oro chiaro.
        TextButton(
          onPressed: () => Navigator.of(context).pop(_face),
          style: TextButton.styleFrom(
            foregroundColor: MilanacColors.goldLight,
            minimumSize: const Size(44, 44),
            textStyle: const TextStyle(
              fontFamily: sportFont,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
          child: const Text('SALVA'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Text(
              'Compare sulla carta, nella rosa e in chat.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.pal.textMuted),
            ),
            const SizedBox(height: 16),
            FaceEditor(
              face: _face,
              onChanged: (f) => setState(() => _face = f),
            ),
          ],
        ),
      ),
    ),
  );
}
