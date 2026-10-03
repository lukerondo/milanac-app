import 'package:flutter/material.dart';

/// Voci del menu laterale. L'ordine qui è l'ordine nel drawer.
class AppSection {
  const AppSection(
    this.path,
    this.title,
    this.icon, {
    this.direttivoOnly = false,
  });
  final String path;
  final String title;
  final IconData icon;

  /// Visibile (e raggiungibile) solo dal Direttivo.
  final bool direttivoOnly;
}

const appSections = <AppSection>[
  AppSection('/', 'Notizie', Icons.newspaper_rounded),
  AppSection(
    '/direttivo',
    'Sala Direttivo',
    Icons.admin_panel_settings_rounded,
    direttivoOnly: true,
  ),
  AppSection('/chat', 'Chat', Icons.forum_rounded),
  AppSection('/presenze', 'Presenze', Icons.how_to_reg_rounded),
  AppSection('/formazione', 'Formazione', Icons.sports_soccer_rounded),
  AppSection('/calendario', 'Calendario partite', Icons.calendar_month_rounded),
  AppSection('/risultati', 'Risultati partite', Icons.scoreboard_rounded),
  AppSection('/tornei', 'Tornei', Icons.leaderboard_rounded),
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
