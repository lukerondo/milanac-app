import 'package:flutter/material.dart';

/// Contatti social mostrati in fondo al menu.
/// In una fase successiva verranno letti dalla tabella `club_links` (modificabile dal Direttivo).
class ClubLink {
  const ClubLink(this.label, this.url, this.icon);
  final String label;
  final String url;
  final IconData icon;
}

const defaultClubLinks = <ClubLink>[
  ClubLink('Instagram', 'https://instagram.com/', Icons.camera_alt_rounded),
  ClubLink('WhatsApp', 'https://wa.me/', Icons.chat_rounded),
  ClubLink('YouTube', 'https://youtube.com/', Icons.play_circle_fill_rounded),
  ClubLink('Sito web', 'https://fabioruggieri13-debug.github.io/MILANAC/', Icons.language_rounded),
];
