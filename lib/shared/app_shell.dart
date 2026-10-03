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
        body: Celebrations(child: child),
      ),
    );
  }
}
