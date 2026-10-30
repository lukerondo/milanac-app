import 'package:flutter/material.dart';

/// Archetipi e PlayStyle come in Pro Clubs. L'archetipo è lo "stile di gioco" della
/// carta (testo libero: questi sono i proposti, con l'icona e cosa fa); i PlayStyle sono
/// abilità con un codice, e i PlayStyle+ (le più forti, in oro) hanno il "+" in fondo.

/// Reparto dell'archetipo, per raggrupparli nell'editor.
enum ArchetypeArea {
  attacco('Attacco'),
  centrocampo('Centrocampo'),
  difesa('Difesa'),
  porta('Porta');

  const ArchetypeArea(this.label);
  final String label;
}

class Archetype {
  const Archetype(this.name, this.area, this.icon, this.description);
  final String name;
  final ArchetypeArea area;
  final IconData icon;
  final String description;
}

/// Gli archetipi proposti (i primi otto c'erano già come stili di gioco).
const archetypes = [
  Archetype(
    'Finalizzatore',
    ArchetypeArea.attacco,
    Icons.gps_fixed_rounded,
    'Vive in area e la butta dentro.',
  ),
  Archetype(
    'Prima punta',
    ArchetypeArea.attacco,
    Icons.height_rounded,
    'Fisico, sponde e colpi di testa.',
  ),
  Archetype(
    'Fantasista',
    ArchetypeArea.attacco,
    Icons.auto_awesome_rounded,
    'Dribbling, estro e giocate decisive.',
  ),
  Archetype(
    'Velocista',
    ArchetypeArea.attacco,
    Icons.bolt_rounded,
    'Allunghi e profondità sulla fascia.',
  ),
  Archetype(
    'Regista',
    ArchetypeArea.centrocampo,
    Icons.hub_rounded,
    'Detta i tempi e accende il gioco.',
  ),
  Archetype(
    'Creatore',
    ArchetypeArea.centrocampo,
    Icons.lightbulb_rounded,
    'Ultimo passaggio e assist.',
  ),
  Archetype(
    'Box to box',
    ArchetypeArea.centrocampo,
    Icons.directions_run_rounded,
    'Da un\'area all\'altra, sempre.',
  ),
  Archetype(
    'Mediano',
    ArchetypeArea.centrocampo,
    Icons.recycling_rounded,
    'Recupera palloni e li rigioca semplice.',
  ),
  Archetype(
    'Muro',
    ArchetypeArea.difesa,
    Icons.shield_rounded,
    'Leader della difesa: non si passa.',
  ),
  Archetype(
    'Costruttore',
    ArchetypeArea.difesa,
    Icons.trending_up_rounded,
    'Imposta da dietro e porta palla.',
  ),
  Archetype(
    'Incursore',
    ArchetypeArea.difesa,
    Icons.double_arrow_rounded,
    'Terzino che spinge e crossa.',
  ),
  Archetype(
    'Saracinesca',
    ArchetypeArea.porta,
    Icons.front_hand_rounded,
    'Riflessi e parate impossibili.',
  ),
  Archetype(
    'Portiere libero',
    ArchetypeArea.porta,
    Icons.open_with_rounded,
    'Esce, anticipa e gioca con i piedi.',
  ),
];

/// L'archetipo di uno stile di gioco scritto sulla carta (maiuscole e spazi non
/// contano), o null se è uno stile scritto a mano.
Archetype? archetypeOf(String? style) {
  final s = style?.trim().toLowerCase();
  if (s == null || s.isEmpty) return null;
  for (final a in archetypes) {
    if (a.name.toLowerCase() == s) return a;
  }
  return null;
}

enum PlayStyleGroup {
  tiro('Tiro'),
  passaggio('Passaggio'),
  pallaAlPiede('Palla al piede'),
  fisico('Fisico'),
  difesa('Difesa'),
  portiere('Portiere');

  const PlayStyleGroup(this.label);
  final String label;
}

class PlayStyle {
  const PlayStyle(this.code, this.name, this.group, this.icon);
  final String code;
  final String name;
  final PlayStyleGroup group;
  final IconData icon;
}

const playStyleCatalog = [
  PlayStyle(
    'tiro_a_giro',
    'Tiro a giro',
    PlayStyleGroup.tiro,
    Icons.rotate_right_rounded,
  ),
  PlayStyle(
    'tiro_potente',
    'Tiro potente',
    PlayStyleGroup.tiro,
    Icons.local_fire_department_rounded,
  ),
  PlayStyle(
    'pallonetto',
    'Pallonetto',
    PlayStyleGroup.tiro,
    Icons.north_east_rounded,
  ),
  PlayStyle(
    'calci_piazzati',
    'Calci piazzati',
    PlayStyleGroup.tiro,
    Icons.flag_rounded,
  ),
  PlayStyle(
    'colpo_di_testa',
    'Colpo di testa',
    PlayStyleGroup.tiro,
    Icons.face_rounded,
  ),
  PlayStyle(
    'acrobatico',
    'Acrobatico',
    PlayStyleGroup.tiro,
    Icons.sports_gymnastics_rounded,
  ),
  PlayStyle(
    'filtrante',
    'Filtrante',
    PlayStyleGroup.passaggio,
    Icons.call_split_rounded,
  ),
  PlayStyle(
    'tiki_taka',
    'Tiki taka',
    PlayStyleGroup.passaggio,
    Icons.swap_horiz_rounded,
  ),
  PlayStyle(
    'lancio_lungo',
    'Lancio lungo',
    PlayStyleGroup.passaggio,
    Icons.open_in_full_rounded,
  ),
  PlayStyle(
    'cross_tagliato',
    'Cross tagliato',
    PlayStyleGroup.passaggio,
    Icons.turn_slight_right_rounded,
  ),
  PlayStyle(
    'primo_controllo',
    'Primo controllo',
    PlayStyleGroup.pallaAlPiede,
    Icons.touch_app_rounded,
  ),
  PlayStyle(
    'tecnico',
    'Tecnico',
    PlayStyleGroup.pallaAlPiede,
    Icons.gesture_rounded,
  ),
  PlayStyle(
    'rapido',
    'Rapido',
    PlayStyleGroup.pallaAlPiede,
    Icons.speed_rounded,
  ),
  PlayStyle(
    'estro',
    'Estro',
    PlayStyleGroup.pallaAlPiede,
    Icons.auto_awesome_rounded,
  ),
  PlayStyle(
    'funambolo',
    'Funambolo',
    PlayStyleGroup.pallaAlPiede,
    Icons.celebration_rounded,
  ),
  PlayStyle(
    'scatto',
    'Scatto bruciante',
    PlayStyleGroup.fisico,
    Icons.bolt_rounded,
  ),
  PlayStyle(
    'instancabile',
    'Instancabile',
    PlayStyleGroup.fisico,
    Icons.all_inclusive_rounded,
  ),
  PlayStyle(
    'a_prova_di_pressing',
    'A prova di pressing',
    PlayStyleGroup.fisico,
    Icons.fitness_center_rounded,
  ),
  PlayStyle(
    'gioco_aereo',
    'Gioco aereo',
    PlayStyleGroup.fisico,
    Icons.flight_takeoff_rounded,
  ),
  PlayStyle('duro', 'Duro', PlayStyleGroup.fisico, Icons.sports_mma_rounded),
  PlayStyle(
    'anticipo',
    'Anticipo',
    PlayStyleGroup.difesa,
    Icons.visibility_rounded,
  ),
  PlayStyle(
    'intercetto',
    'Intercetto',
    PlayStyleGroup.difesa,
    Icons.block_rounded,
  ),
  PlayStyle('muro', 'Muro', PlayStyleGroup.difesa, Icons.shield_rounded),
  PlayStyle(
    'scivolata',
    'Scivolata',
    PlayStyleGroup.difesa,
    Icons.south_east_rounded,
  ),
  PlayStyle(
    'marcatura',
    'Marcatura',
    PlayStyleGroup.difesa,
    Icons.compare_arrows_rounded,
  ),
  PlayStyle(
    'riflessi',
    'Riflessi',
    PlayStyleGroup.portiere,
    Icons.flash_on_rounded,
  ),
  PlayStyle(
    'uscite',
    'Uscite',
    PlayStyleGroup.portiere,
    Icons.directions_run_rounded,
  ),
  PlayStyle(
    'presa_alta',
    'Presa alta',
    PlayStyleGroup.portiere,
    Icons.pan_tool_rounded,
  ),
  PlayStyle(
    'piedi_buoni',
    'Piedi buoni',
    PlayStyleGroup.portiere,
    Icons.sports_soccer_rounded,
  ),
  PlayStyle(
    'rinvio_lungo',
    'Rinvio lungo',
    PlayStyleGroup.portiere,
    Icons.call_made_rounded,
  ),
];

/// Quanti PlayStyle si scelgono al massimo, e quanti di questi possono essere "+".
const maxPlayStyles = 6, maxPlayStylesPlus = 2;

/// Un PlayStyle scelto: quale, e se è un PlayStyle+.
typedef ChosenPlayStyle = ({PlayStyle style, bool plus});

/// I PlayStyle scelti, dai codici salvati ("tiro_potente+", "scatto"): prima i "+",
/// poi gli altri, nell'ordine scelto. I codici sconosciuti (di una versione più nuova
/// dell'app) si saltano.
List<ChosenPlayStyle> chosenPlayStyles(Iterable<String> codes) {
  final chosen = <ChosenPlayStyle>[];
  for (final c in codes) {
    final plus = c.endsWith('+');
    final code = plus ? c.substring(0, c.length - 1) : c;
    final style = playStyleCatalog.where((p) => p.code == code).firstOrNull;
    if (style != null) chosen.add((style: style, plus: plus));
  }
  return [
    for (final c in chosen)
      if (c.plus) c,
    for (final c in chosen)
      if (!c.plus) c,
  ];
}
