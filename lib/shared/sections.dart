import 'package:flutter/material.dart';

/// Voci del menu laterale. L'ordine qui è l'ordine nel drawer.
class AppSection {
  const AppSection(this.path, this.title, this.icon);
  final String path;
  final String title;
  final IconData icon;
}

const appSections = <AppSection>[
  AppSection('/', 'Notizie', Icons.newspaper_rounded),
  AppSection('/chat', 'Chat', Icons.forum_rounded),
  AppSection('/presenze', 'Presenze', Icons.how_to_reg_rounded),
  AppSection('/formazione', 'Formazione', Icons.sports_soccer_rounded),
  AppSection('/calendario', 'Calendario partite', Icons.calendar_month_rounded),
  AppSection('/risultati', 'Risultati partite', Icons.scoreboard_rounded),
  AppSection('/rosa', 'Rosa completa', Icons.groups_rounded),
  AppSection('/carta', 'La mia carta', Icons.style_rounded),
  AppSection('/tattiche', 'Tattiche & Build', Icons.draw_rounded),
  AppSection('/albo-doro', "Albo d'oro", Icons.emoji_events_rounded),
  AppSection('/regolamento', 'Regolamento & Storia', Icons.menu_book_rounded),
  AppSection('/musica', 'Colonna sonora', Icons.library_music_rounded),
];

AppSection sectionFor(String path) => appSections.firstWhere(
  (s) => s.path == path,
  orElse: () => appSections.first,
);
