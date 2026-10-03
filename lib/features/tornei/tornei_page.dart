import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../risultati/matches_repository.dart';
import '../risultati/risultati_page.dart' show MatchCard;
import 'tournaments_repository.dart';

/// Tornei del club: link al sito dell'organizzatore e classifica facoltativa.
class TorneiPage extends ConsumerStatefulWidget {
  const TorneiPage({super.key});

  @override
  ConsumerState<TorneiPage> createState() => _TorneiPageState();
}

class _TorneiPageState extends ConsumerState<TorneiPage> {
  Team? _team;

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final tournaments = ref.watch(tournamentsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () => showTournamentEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuovo torneo'),
            )
          : null,
      body: tournaments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (all) {
          final shown = all.where((t) => _team == null || t.team == _team);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              TeamFilter(
                value: _team,
                onChanged: (t) => setState(() => _team = t),
              ),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'Nessun torneo registrato.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              for (final status in [
                TournamentStatus.inCorso,
                TournamentStatus.iscrizioni,
                TournamentStatus.concluso,
              ])
                if (shown.any((t) => t.status == status)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      status.label.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  for (final t in shown.where((t) => t.status == status))
                    _TournamentCard(tournament: t),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _TournamentCard extends ConsumerWidget {
  const _TournamentCard({required this.tournament});
  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final standings = ref.watch(standingsProvider(t.id)).value ?? const [];
    final ourIndex = standings.indexWhere((r) => r.isUs);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: const CircleAvatar(
          backgroundColor: MilanacColors.surfaceHigh,
          child: Icon(Icons.leaderboard_rounded, color: MilanacColors.gold),
        ),
        title: Text(
          t.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (t.organizer != null) t.organizer!,
                if (ourIndex >= 0)
                  '${ourIndex + 1}° posto · ${standings[ourIndex].points} pt',
              ].join(' · '),
            ),
            const SizedBox(height: 4),
            TeamBadge(t.team, small: true),
          ],
        ),
        trailing: t.url == null
            ? const Icon(Icons.chevron_right_rounded)
            : IconButton(
                tooltip: 'Sito del torneo',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => _open(t.url!),
              ),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => TournamentPage(tournamentId: t.id)),
        ),
      ),
    );
  }
}

void _open(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Dettaglio: info, sito, classifica e partite del torneo.
class TournamentPage extends ConsumerWidget {
  const TournamentPage({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final t = ref
        .watch(tournamentsProvider)
        .value
        ?.where((x) => x.id == tournamentId)
        .firstOrNull;
    final standings = ref.watch(standingsProvider(tournamentId));
    final matches = (ref.watch(matchesProvider).value ?? const [])
        .where((m) => m.tournamentId == tournamentId)
        .toList();
    final dates = DateFormat('d MMM yyyy', 'it');

    return Scaffold(
      appBar: AppBar(
        title: const Text('TORNEO'),
        actions: [
          if (isDirettivo && t != null)
            IconButton(
              tooltip: 'Modifica torneo',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => showTournamentEditor(context, tournament: t),
            ),
        ],
      ),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TeamBadge(t.team),
                    Text(
                      t.status.label,
                      style: const TextStyle(color: MilanacColors.gold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t.name,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (t.organizer != null)
                  Text(
                    t.organizer!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (t.startsOn != null)
                  Text(
                    t.endsOn == null
                        ? 'Dal ${dates.format(t.startsOn!)}'
                        : 'Dal ${dates.format(t.startsOn!)} al ${dates.format(t.endsOn!)}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                if (t.notes != null && t.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t.notes!),
                ],
                if (t.url != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _open(t.url!),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Apri il sito del torneo'),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CLASSIFICA',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    if (isDirettivo)
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StandingsEditorPage(
                              tournamentId: t.id,
                              initial: standings.value ?? const [],
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Aggiorna'),
                      ),
                  ],
                ),
                switch (standings) {
                  AsyncData(:final value) when value.isNotEmpty =>
                    StandingsTable(rows: value),
                  AsyncData() => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Classifica non inserita: si trova sul sito del torneo.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  AsyncError(:final error) => Text('Errore: $error'),
                  _ => const LinearProgressIndicator(),
                },
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'PARTITE',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final m in matches) MatchCard(match: m),
                ],
              ],
            ),
    );
  }
}

/// Tabella della classifica (Pos, Squadra, G, V, N, P, DR, Pt).
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.rows});
  final List<StandingRow> rows;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(
      color: Colors.white54,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text, {TextStyle? style, double width = 28}) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  cell('#', style: head, width: 24),
                  const Expanded(child: Text('Squadra', style: head)),
                  for (final h in ['G', 'V', 'N', 'P', 'DR'])
                    cell(h, style: head),
                  cell('Pt', style: head, width: 32),
                ],
              ),
            ),
            for (final (i, r) in rows.indexed)
              Container(
                color: r.isUs ? MilanacColors.red.withValues(alpha: .22) : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    cell('${i + 1}', width: 24),
                    Expanded(
                      child: Text(
                        r.teamName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: r.isUs
                              ? FontWeight.w900
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    for (final v in [r.played, r.won, r.drawn, r.lost])
                      cell('$v'),
                    cell(r.goalDiff > 0 ? '+${r.goalDiff}' : '${r.goalDiff}'),
                    cell(
                      '${r.points}',
                      width: 32,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: MilanacColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ editor

Future<void> showTournamentEditor(
  BuildContext context, {
  Tournament? tournament,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _TournamentEditor(tournament: tournament),
);

class _TournamentEditor extends ConsumerStatefulWidget {
  const _TournamentEditor({this.tournament});
  final Tournament? tournament;

  @override
  ConsumerState<_TournamentEditor> createState() => _TournamentEditorState();
}

class _TournamentEditorState extends ConsumerState<_TournamentEditor> {
  late final _name = TextEditingController(text: widget.tournament?.name);
  late final _organizer = TextEditingController(
    text: widget.tournament?.organizer,
  );
  late final _url = TextEditingController(text: widget.tournament?.url);
  late final _notes = TextEditingController(text: widget.tournament?.notes);
  late Team _team = widget.tournament?.team ?? Team.milanac;
  late TournamentStatus _status =
      widget.tournament?.status ?? TournamentStatus.inCorso;
  late DateTime? _startsOn = widget.tournament?.startsOn;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _organizer, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    var url = _text(_url);
    if (url != null && !url.contains('://')) url = 'https://$url';
    if (_text(_name) == null ||
        (url != null && Uri.tryParse(url)?.host.isNotEmpty != true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome e un link valido.')),
      );
      return;
    }
    setState(() => _saving = true);
    final t = Tournament(
      id: widget.tournament?.id ?? '',
      name: _text(_name)!,
      organizer: _text(_organizer),
      url: url,
      team: _team,
      status: _status,
      startsOn: _startsOn,
      endsOn: widget.tournament?.endsOn,
      notes: _text(_notes),
    );
    try {
      await ref.read(tournamentsRepositoryProvider).save(t);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminare il torneo?'),
        content: const Text('Le partite restano, senza torneo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await ref.read(tournamentsRepositoryProvider).delete(widget.tournament!.id);
    nav
      ..pop()
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tournament == null ? 'Nuovo torneo' : 'Modifica torneo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SegmentedButton<Team>(
              segments: [
                for (final t in Team.values)
                  ButtonSegment(value: t, label: Text(t.short)),
              ],
              selected: {_team},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _team = s.first),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nome del torneo',
                hintText: 'es. FVPA Serie B',
              ),
            ),
            TextField(
              controller: _organizer,
              decoration: const InputDecoration(
                labelText: 'Organizzatore (facoltativo)',
              ),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Sito o pagina del torneo (facoltativo)',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final s in TournamentStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(
                _startsOn == null
                    ? 'Data di inizio (facoltativa)'
                    : 'Inizio: ${DateFormat('d MMMM yyyy', 'it').format(_startsOn!)}',
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _startsOn ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(DateTime.now().year + 2),
                );
                if (d != null) setState(() => _startsOn = d);
              },
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (facoltative)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salva torneo'),
              ),
            ),
            if (widget.tournament != null)
              TextButton(
                onPressed: _saving ? null : _delete,
                child: const Text(
                  'Elimina torneo',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Il Direttivo aggiorna la classifica: una riga per squadra (V, N, P, gol).
class StandingsEditorPage extends ConsumerStatefulWidget {
  const StandingsEditorPage({
    super.key,
    required this.tournamentId,
    required this.initial,
  });
  final String tournamentId;
  final List<StandingRow> initial;

  @override
  ConsumerState<StandingsEditorPage> createState() =>
      _StandingsEditorPageState();
}

class _StandingsEditorPageState extends ConsumerState<StandingsEditorPage> {
  late final _rows = List.of(widget.initial);
  bool _saving = false;

  Future<void> _edit([int? index]) async {
    final row = await showDialog<StandingRow>(
      context: context,
      builder: (_) =>
          _StandingRowDialog(row: index == null ? null : _rows[index]),
    );
    if (row == null) return;
    setState(() {
      // Una sola riga può essere "noi".
      if (row.isUs) {
        for (final (i, r) in _rows.indexed) {
          if (r.isUs && i != index) {
            _rows[i] = StandingRow(
              teamName: r.teamName,
              won: r.won,
              drawn: r.drawn,
              lost: r.lost,
              goalsFor: r.goalsFor,
              goalsAgainst: r.goalsAgainst,
            );
          }
        }
      }
      index == null ? _rows.add(row) : _rows[index] = row;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(tournamentsRepositoryProvider)
          .saveStandings(widget.tournamentId, _rows);
      ref.invalidate(standingsProvider(widget.tournamentId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CLASSIFICA'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('SALVA'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MilanacColors.red,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Aggiungi squadra'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          const Text(
            'Punti e partite giocate si calcolano da vittorie, pareggi e sconfitte. '
            "Tocca una riga per modificarla, tieni premuto per toglierla.",
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 8),
          if (_rows.isNotEmpty) StandingsTable(rows: sortStandings(_rows)),
          for (final (i, r) in _rows.indexed)
            ListTile(
              title: Text(r.teamName),
              subtitle: Text(
                'V ${r.won} · N ${r.drawn} · P ${r.lost} · Gol ${r.goalsFor}-${r.goalsAgainst}',
              ),
              trailing: r.isUs
                  ? const Icon(Icons.star_rounded, color: MilanacColors.gold)
                  : null,
              onTap: () => _edit(i),
              onLongPress: () => setState(() => _rows.removeAt(i)),
            ),
        ],
      ),
    );
  }
}

class _StandingRowDialog extends StatefulWidget {
  const _StandingRowDialog({this.row});
  final StandingRow? row;

  @override
  State<_StandingRowDialog> createState() => _StandingRowDialogState();
}

class _StandingRowDialogState extends State<_StandingRowDialog> {
  late final _name = TextEditingController(text: widget.row?.teamName);
  late final _fields = {
    'V': TextEditingController(text: '${widget.row?.won ?? 0}'),
    'N': TextEditingController(text: '${widget.row?.drawn ?? 0}'),
    'P': TextEditingController(text: '${widget.row?.lost ?? 0}'),
    'GF': TextEditingController(text: '${widget.row?.goalsFor ?? 0}'),
    'GS': TextEditingController(text: '${widget.row?.goalsAgainst ?? 0}'),
  };
  late bool _isUs = widget.row?.isUs ?? false;

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(String k) => int.tryParse(_fields[k]!.text) ?? 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.row == null ? 'Nuova squadra' : 'Modifica squadra'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Squadra'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(:key, :value) in _fields.entries)
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: value,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: key),
                  ),
                ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _isUs,
            onChanged: (v) => setState(() => _isUs = v ?? false),
            title: const Text('È la nostra squadra'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            StandingRow(
              teamName: _name.text.trim(),
              won: _n('V'),
              drawn: _n('N'),
              lost: _n('P'),
              goalsFor: _n('GF'),
              goalsAgainst: _n('GS'),
              isUs: _isUs,
            ),
          );
        },
        child: const Text('OK'),
      ),
    ],
  );
}
