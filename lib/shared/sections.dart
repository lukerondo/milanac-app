import 'package:flutter/material.dart';

/// Gruppi del menu laterale: la squadra (la vita di tutti i giorni), il club e la
/// parte riservata al Direttivo.
enum SectionGroup {
  home(''),
  squadra('Squadra'),
  club('Club'),
  direttivo('Direttivo');

  const SectionGroup(this.label);
  final String label;
}

/// Voci del menu laterale. L'ordine qui è l'ordine nel drawer.
class AppSection {
  const AppSection(
    this.path,
    this.title,
    this.icon, {
    this.group = SectionGroup.club,
    this.direttivoOnly = false,
    this.shortTitle,
  });
  final String path;
  final String title;
  final IconData icon;
  final SectionGroup group;

  /// Titolo per la barra in alto, se diverso da quello del menu.
  final String? shortTitle;
  String get barTitle => shortTitle ?? title;

  /// Visibile (e raggiungibile) solo dal Direttivo.
  final bool direttivoOnly;
}

const appSections = <AppSection>[
  AppSection(
    '/',
    'Home',
    Icons.home_rounded,
    group: SectionGroup.home,
    shortTitle: 'Milan AC Pro Club',
  ),
  // La squadra, giorno per giorno.
  AppSection(
    '/presenze',
    'Presenze',
    Icons.how_to_reg_rounded,
    group: SectionGroup.squadra,
  ),
  AppSection(
    '/formazione',
    'Formazione',
    Icons.sports_soccer_rounded,
    group: SectionGroup.squadra,
  ),
  AppSection(
    '/calendario',
    'Calendario',
    Icons.calendar_month_rounded,
    group: SectionGroup.squadra,
  ),
  AppSection(
    '/risultati',
    'Risultati',
    Icons.scoreboard_rounded,
    group: SectionGroup.squadra,
  ),
  AppSection('/chat', 'Chat', Icons.forum_rounded, group: SectionGroup.squadra),
  // Il club.
  AppSection('/mondo', 'Mondo Proclub', Icons.public_rounded),
  AppSection('/rosa', 'Rosa completa', Icons.groups_rounded),
  AppSection('/carta', 'La mia carta', Icons.style_rounded),
  AppSection('/carte-speciali', 'Carte speciali', Icons.military_tech_rounded),
  AppSection('/tornei', 'Tornei', Icons.leaderboard_rounded),
  AppSection('/albo-doro', "Albo d'oro", Icons.emoji_events_rounded),
  AppSection('/regolamento', 'Regolamento & Storia', Icons.menu_book_rounded),
  AppSection('/tattiche', 'Tattiche & Build', Icons.draw_rounded),
  AppSection('/musica', 'Colonna sonora', Icons.library_music_rounded),
  // Riservato.
  AppSection(
    '/direttivo',
    'Sala Direttivo',
    Icons.admin_panel_settings_rounded,
    group: SectionGroup.direttivo,
    direttivoOnly: true,
  ),
];

AppSection sectionFor(String path) => appSections.firstWhere(
  (s) => s.path == path,
  orElse: () => appSections.first,
);
