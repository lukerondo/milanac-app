import 'package:flutter/material.dart';

import '../../core/theme.dart';
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
  Widget build(BuildContext context) => StadiumBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('IL TUO VOLTO'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_face),
            child: const Text(
              'SALVA',
              style: TextStyle(color: MilanacColors.gold),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              FaceEditor(
                face: _face,
                onChanged: (f) => setState(() => _face = f),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
