import 'package:flutter/material.dart';

import '../features/impostazioni/impostazioni_page.dart';
import '../features/musica/musica_page.dart';
import '../core/theme.dart';
import '../features/walkout/celebrations.dart';
import 'app_drawer.dart';
import 'sections.dart';

/// Struttura comune a tutte le sezioni: barra in alto + menu laterale.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StadiumBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(sectionFor(path).barTitle.toUpperCase()),
          actions: const [SoundtrackButton(), SettingsButton()],
        ),
        drawer: AppDrawer(currentPath: path),
        body: Celebrations(child: ContentWidth(child: child)),
      ),
    );
  }
}

/// Larghezza massima del contenuto: sui tablet le sezioni restano una colonna
/// leggibile al centro; sui telefoni non cambia nulla.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;

  static const maxWidth = 720.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <= maxWidth) return child;
      return Center(
        child: SizedBox(
          width: maxWidth,
          height: constraints.maxHeight,
          child: child,
        ),
      );
    },
  );
}
