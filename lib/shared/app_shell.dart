import 'package:flutter/material.dart';

import 'app_drawer.dart';
import 'sections.dart';

/// Struttura comune a tutte le sezioni: barra in alto + menu laterale.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(sectionFor(path).title.toUpperCase())),
      drawer: AppDrawer(currentPath: path),
      body: child,
    );
  }
}
