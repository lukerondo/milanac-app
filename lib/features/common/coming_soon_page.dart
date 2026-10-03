import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/sections.dart';

/// Segnaposto per le sezioni che verranno sviluppate nelle prossime fasi.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final section = sectionFor(path);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 72, color: MilanacColors.gold),
            const SizedBox(height: 16),
            Text(
              section.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sezione in arrivo nelle prossime fasi di sviluppo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
