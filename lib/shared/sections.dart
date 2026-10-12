import 'package:flutter/material.dart';

/// Le cinque schede della barra in basso, nell'ordine dei rami del router.
enum MainTab {
  home('Home', Icons.home_outlined, Icons.home_rounded, '/'),
  presenze(
    'Presenze',
    Icons.event_available_outlined,
    Icons.event_available_rounded,
    '/presenze',
  ),
  partite(
    'Partite',
    Icons.sports_soccer_outlined,
    Icons.sports_soccer_rounded,
    '/partite',
  ),
  chat(
    'Chat',
    Icons.chat_bubble_outline_rounded,
    Icons.chat_bubble_rounded,
    '/chat',
  ),
  club('Club', Icons.shield_outlined, Icons.shield_rounded, '/club');

  const MainTab(this.label, this.icon, this.selectedIcon, this.path);
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Pagina iniziale della scheda.
  final String path;
}

/// Una sezione dell'app: rotta, titolo nella barra in alto, scheda a cui appartiene
/// e sezione "madre" (dove porta il tasto indietro se la si apre da una notifica).
class AppSection {
  const AppSection(
    this.path,
    this.title,
    this.icon, {
    required this.tab,
    this.parent,
    this.subtitle,
    this.direttivoOnly = false,
  });

  final String path;
  final String title;
  final IconData icon;
  final MainTab tab;

  /// null = pagina iniziale di una scheda.
  final String? parent;

  /// Descrizione breve (voci della pagina Club).
  final String? subtitle;

  /// Visibile (e raggiungibile) solo dal Direttivo.
  final bool direttivoOnly;
}

const appSections = <AppSection>[
  AppSection('/', 'Home', Icons.home_rounded, tab: MainTab.home),
  AppSection(
    '/presenze',
    'Presenze',
    Icons.event_available_rounded,
    tab: MainTab.presenze,
  ),
  AppSection(
    '/partite',
    'Partite',
    Icons.sports_soccer_rounded,
    tab: MainTab.partite,
  ),
  AppSection(
    '/formazione',
    'Formazione',
    Icons.sports_soccer_rounded,
    tab: MainTab.partite,
    parent: '/partite',
  ),
  AppSection('/chat', 'Chat', Icons.chat_bubble_rounded, tab: MainTab.chat),
  AppSection('/club', 'Club', Icons.shield_rounded, tab: MainTab.club),
  // Le voci della pagina Club, nell'ordine in cui compaiono.
  AppSection(
    '/rosa',
    'Rosa',
    Icons.groups_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'Carte, ruoli, squadre',
  ),
  AppSection(
    '/carte-speciali',
    'Carte speciali',
    Icons.military_tech_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'Le premiate della settimana',
  ),
  AppSection(
    '/tattiche',
    'Tattiche',
    Icons.draw_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'Lavagna, schemi e build',
  ),
  AppSection(
    '/mondo',
    'Mondo Proclub',
    Icons.public_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'Video e notizie',
  ),
  AppSection(
    '/albo-doro',
    "Albo d'oro",
    Icons.emoji_events_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'I trofei del club',
  ),
  AppSection(
    '/regolamento',
    'Regolamento e Storia',
    Icons.menu_book_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'Le regole, chi siamo',
  ),
  AppSection(
    '/musica',
    'Colonna sonora',
    Icons.library_music_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'La musica di sottofondo',
  ),
  AppSection(
    '/direttivo',
    'Sala Direttivo',
    Icons.admin_panel_settings_rounded,
    tab: MainTab.club,
    parent: '/club',
    subtitle: 'Solo per il Direttivo',
    direttivoOnly: true,
  ),
];

/// Voci della pagina Club (tutte le sezioni con madre "/club", tranne la Sala
/// Direttivo che ha il suo pulsante).
final clubSections = [
  for (final s in appSections)
    if (s.parent == '/club' && !s.direttivoOnly) s,
];

AppSection sectionFor(String path) => appSections.firstWhere(
  (s) => s.path == path,
  orElse: () => appSections.first,
);
