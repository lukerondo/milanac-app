import 'package:flutter/material.dart';

import 'theme.dart';

/// Le due squadre del club: un giocatore può stare in una o in entrambe.
enum Team {
  milanac('MILANAC', 'MILANAC', MilanacColors.red),
  futuro('MILANAC FUTURO', 'FUTURO', Color(0xFF9CA3AF));

  const Team(this.label, this.short, this.color);
  final String label;
  final String short;
  final Color color;

  static Team? parse(Object? value) => Team.values.asNameMap()[value];

  /// Legge la colonna `teams` (array di testo); se vuota il giocatore è in MILANAC.
  static Set<Team> parseSet(Object? value) {
    final teams = {
      if (value is List)
        for (final v in value) ?parse(v),
    };
    return teams.isEmpty ? {Team.milanac} : teams;
  }
}

/// Nomi delle squadre nell'ordine fisso (MILANAC prima), per salvarle nel database.
List<String> teamsToJson(Set<Team> teams) => [
  for (final t in Team.values)
    if (teams.contains(t)) t.name,
];

/// Etichetta colorata con il nome breve della squadra.
class TeamBadge extends StatelessWidget {
  const TeamBadge(this.team, {super.key, this.small = false});
  final Team team;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final filled = team == Team.milanac;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: filled ? team.color : Colors.transparent,
        border: Border.all(color: team.color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        team.short,
        style: TextStyle(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
          color: filled ? Colors.white : team.color,
        ),
      ),
    );
  }
}

/// Scelta di una o entrambe le squadre (almeno una resta sempre selezionata).
class TeamsPicker extends StatelessWidget {
  const TeamsPicker({super.key, required this.value, required this.onChanged});
  final Set<Team> value;
  final ValueChanged<Set<Team>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final t in Team.values)
        FilterChip(
          label: Text(t.label),
          selected: value.contains(t),
          onSelected: (on) {
            final next = {...value};
            on ? next.add(t) : next.remove(t);
            if (next.isNotEmpty) onChanged(next);
          },
        ),
    ],
  );
}

/// Filtro "Tutte / MILANAC / FUTURO" usato in Rosa e Risultati (null = tutte).
class TeamFilter extends StatelessWidget {
  const TeamFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.counts,
  });
  final Team? value;
  final ValueChanged<Team?> onChanged;

  /// Numero di elementi per ciascuna scelta (chiave null = tutte), facoltativo.
  final Map<Team?, int>? counts;

  @override
  Widget build(BuildContext context) {
    String label(String text, Team? t) =>
        counts == null ? text : '$text (${counts![t] ?? 0})';
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: Text(label('Tutte', null)),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final t in Team.values)
          ChoiceChip(
            label: Text(label(t.short, t)),
            selected: value == t,
            onSelected: (_) => onChanged(t),
          ),
      ],
    );
  }
}
