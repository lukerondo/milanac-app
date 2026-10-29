import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../carta/card_stats.dart' show scorerPerGoal;
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import '../tornei/tournaments_repository.dart';
import 'match.dart';
import 'matches_repository.dart';

/// Il risultato si scrive per intero o per niente: con un solo punteggio la partita
/// resterebbe "da giocare" (niente notifica, niente carte). null = va bene.
String? resultError(int? goalsFor, int? goalsAgainst) =>
    (goalsFor == null) == (goalsAgainst == null)
    ? null
    : 'Inserisci entrambi i punteggi, oppure lasciali vuoti '
          'se la partita non è ancora stata giocata.';

Future<void> showMatchEditor(BuildContext context, {ClubMatch? match}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MatchEditor(match: match),
    );

class _MatchEditor extends ConsumerStatefulWidget {
  const _MatchEditor({this.match});
  final ClubMatch? match;

  @override
  ConsumerState<_MatchEditor> createState() => _MatchEditorState();
}

class _MatchEditorState extends ConsumerState<_MatchEditor> {
  late MatchKind _kind = widget.match?.kind ?? MatchKind.torneo;
  late Team _team = widget.match?.team ?? Team.milanac;
  late String? _tournamentId = widget.match?.tournamentId;
  late String? _goalkeeperId = widget.match?.goalkeeperId;
  late bool _home = widget.match?.home ?? true;

  /// Il giorno della partita in Italia (di una nuova: oggi in Italia).
  late DateTime _date =
      widget.match?.playedAt ?? italianDay(ref.read(clockProvider)());
  late final _opponent = TextEditingController(text: widget.match?.opponent);
  late final _competition = TextEditingController(
    text: widget.match?.competition,
  );
  late final _for = TextEditingController(
    text: widget.match?.goalsFor?.toString(),
  );
  late final _against = TextEditingController(
    text: widget.match?.goalsAgainst?.toString(),
  );
  late final _scorers = TextEditingController(text: widget.match?.scorers);
  late final _notes = TextEditingController(text: widget.match?.notes);

  /// Minuti dei gol (facoltativi): uno per gol del risultato, i nostri nell'ordine dei
  /// marcatori, poi quelli subiti. Crescono con il risultato e non si accorciano, così
  /// un punteggio corretto per sbaglio non fa perdere i minuti già scritti.
  final _ourMinutes = <TextEditingController>[];
  final _theirMinutes = <TextEditingController>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.match;
    if (m != null) {
      // Ogni minuto salvato torna sulla riga del suo marcatore (poi i rimasti in ordine).
      final ours = [
        for (final g in m.timeline)
          if (g.ours) g,
      ];
      final names = scorerPerGoal(m.scorers);
      final rows = List<int?>.filled(m.goalsFor ?? 0, null);
      final taken = List<bool>.filled(ours.length, false);
      for (var i = 0; i < rows.length; i++) {
        final name = i < names.length ? names[i].toLowerCase() : null;
        final j = ours.indexed
            .where((e) => !taken[e.$1] && e.$2.scorer?.toLowerCase() == name)
            .firstOrNull
            ?.$1;
        if (name != null && j != null) {
          taken[j] = true;
          rows[i] = ours[j].minute;
        }
      }
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] != null) continue;
        final j = taken.indexWhere((t) => !t);
        if (j < 0) break;
        taken[j] = true;
        rows[i] = ours[j].minute;
      }
      _ourMinutes.addAll([
        for (final r in rows) TextEditingController(text: r?.toString()),
      ]);
      _theirMinutes.addAll([
        for (final g in m.timeline)
          if (!g.ours) TextEditingController(text: '${g.minute}'),
      ]);
    }
    for (final c in [_for, _against, _scorers]) {
      c.addListener(_refresh);
    }
  }

  /// Le righe dei minuti seguono il risultato e i marcatori mentre si scrivono.
  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _opponent,
      _competition,
      _for,
      _against,
      _scorers,
      _notes,
      ..._ourMinutes,
      ..._theirMinutes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// I primi [count] campi dei minuti, aggiungendo quelli che mancano.
  List<TextEditingController> _minutes(
    List<TextEditingController> list,
    int count,
  ) {
    while (list.length < count) {
      list.add(TextEditingController());
    }
    return list.sublist(0, count);
  }

  /// Minuto scritto in un campo: null se vuoto, -1 se fuori misura.
  static int? _minuteIn(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final m = int.tryParse(text);
    return m == null || m < 1 || m > MatchGoal.maxMinute ? -1 : m;
  }

  /// I gol con il minuto da salvare (null = un minuto non valido).
  List<MatchGoal>? _timeline(int goalsFor, int goalsAgainst) {
    final names = scorerPerGoal(_scorers.text);
    final goals = <MatchGoal>[];
    for (final (i, c) in _minutes(_ourMinutes, goalsFor).indexed) {
      final minute = _minuteIn(c);
      if (minute == -1) return null;
      if (minute == null) continue;
      final name = i < names.length ? names[i] : null;
      goals.add(
        MatchGoal(
          minute: minute,
          ours: true,
          scorer: name == null || name.length <= 60
              ? name
              : name.substring(0, 60),
        ),
      );
    }
    for (final c in _minutes(_theirMinutes, goalsAgainst)) {
      final minute = _minuteIn(c);
      if (minute == -1) return null;
      if (minute != null) goals.add(MatchGoal(minute: minute, ours: false));
    }
    return sortedGoals(goals);
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final goalsFor = int.tryParse(_for.text.trim());
    final goalsAgainst = int.tryParse(_against.text.trim());
    final timeline = _timeline(goalsFor ?? 0, goalsAgainst ?? 0);
    final error = _opponent.text.trim().isEmpty
        ? "Inserisci il nome dell'avversario."
        : resultError(goalsFor, goalsAgainst) ??
              (timeline == null
                  ? 'Minuto non valido: scrivi un numero da 1 a '
                        '${MatchGoal.maxMinute}.'
                  : null);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    final m = ClubMatch(
      id: widget.match?.id ?? '',
      kind: _kind,
      opponent: _opponent.text.trim(),
      // Le 21:30 italiane del giorno scelto (vedi ClubMatch.playedAt).
      playedAt: DateTime.utc(_date.year, _date.month, _date.day, 21, 30),
      competition: _kind == MatchKind.torneo ? _text(_competition) : null,
      home: _home,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
      scorers: _text(_scorers),
      notes: _text(_notes),
      team: _team,
      tournamentId: _tournamentId,
      goalkeeperId: _goalkeeperId,
      timeline: timeline!,
    );
    final repo = ref.read(matchesRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.save(m);
      // Una vittoria si sente come un gol; il resto come una conferma.
      (goalsFor ?? 0) > (goalsAgainst ?? 0)
          ? Haptics.goal()
          : Haptics.confirm();
      if (mounted) Navigator.of(context).pop();
      if (m.timeline.isNotEmpty && repo.timelineMissing) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Partita salvata. I minuti dei gol si vedranno quando il server '
              'del club sarà aggiornato.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget goals(TextEditingController c, String label) => SizedBox(
      width: 72,
      child: TextField(
        controller: c,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        decoration: InputDecoration(labelText: label),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.match == null ? 'Nuova partita' : 'Modifica partita',
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
            const SizedBox(height: 8),
            SegmentedButton<MatchKind>(
              segments: const [
                ButtonSegment(
                  value: MatchKind.torneo,
                  label: Text('Torneo ufficiale'),
                ),
                ButtonSegment(
                  value: MatchKind.amichevole,
                  label: Text('Amichevole'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            if (_kind == MatchKind.torneo) ...[
              const SizedBox(height: 8),
              _TournamentPicker(
                team: _team,
                value: _tournamentId,
                onChanged: (t) => setState(() {
                  _tournamentId = t?.id;
                  if (t != null && _competition.text.trim().isEmpty) {
                    _competition.text = t.name;
                  }
                }),
              ),
              TextField(
                controller: _competition,
                decoration: const InputDecoration(
                  labelText: 'Torneo / giornata',
                  hintText: 'es. FVPA Serie B – 3ª giornata',
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _opponent,
              decoration: const InputDecoration(labelText: 'Avversario'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Giocata in casa'),
              value: _home,
              onChanged: (v) => setState(() => _home = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(DateFormat('EEEE d MMMM yyyy', 'it').format(_date)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                goals(_for, _team.short),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                ),
                goals(_against, 'Avversari'),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Lascia vuoto il punteggio se la partita non è ancora stata giocata.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.pal.textMuted),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _scorers,
              decoration: const InputDecoration(
                labelText: 'Marcatori',
                hintText: 'es. Rossi (2), Bianchi',
              ),
            ),
            ..._minuteRows(context),
            const SizedBox(height: 8),
            _GoalkeeperPicker(
              team: _team,
              value: _goalkeeperId,
              onChanged: (id) => setState(() => _goalkeeperId = id),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note / commento'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salva partita'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on _MatchEditorState {
  /// Un campo per il minuto di ogni gol del risultato: i nostri con il nome del
  /// marcatore (dall'elenco), poi quelli subiti.
  List<Widget> _minuteRows(BuildContext context) {
    final p = context.pal;
    final goalsFor = int.tryParse(_for.text.trim()) ?? 0;
    final goalsAgainst = int.tryParse(_against.text.trim()) ?? 0;
    if (goalsFor + goalsAgainst == 0) return const [];
    final names = scorerPerGoal(_scorers.text);
    Widget row(String label, TextEditingController c, Key key, bool ours) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(
                Icons.sports_soccer_rounded,
                size: 20,
                color: ours ? p.accentText : p.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              SizedBox(
                width: 84,
                child: TextField(
                  key: key,
                  controller: c,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'min',
                    suffixText: "'",
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        );
    return [
      const SizedBox(height: 14),
      Text('Minuti dei gol', style: Theme.of(context).textTheme.titleSmall),
      Text(
        'Facoltativi: servono per il tabellone e la cronaca della partita.',
        style: TextStyle(fontSize: 13, color: p.textMuted),
      ),
      for (final (i, c) in _minutes(_ourMinutes, goalsFor).indexed)
        row(
          i < names.length ? names[i] : 'Gol ${i + 1} del ${_team.short}',
          c,
          Key('minuto-noi-$i'),
          true,
        ),
      for (final (i, c) in _minutes(_theirMinutes, goalsAgainst).indexed)
        row(
          goalsAgainst == 1 ? 'Gol subito' : 'Gol subito ${i + 1}',
          c,
          Key('minuto-loro-$i'),
          false,
        ),
    ];
  }
}

/// Portiere della partita: se non si sceglie, al primo risultato viene preso dalla
/// formazione pubblicata. Conta per la carta blu elettrico (tre partite senza subire gol).
class _GoalkeeperPicker extends ConsumerWidget {
  const _GoalkeeperPicker({
    required this.team,
    required this.value,
    required this.onChanged,
  });
  final Team team;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        (ref.watch(rosaProvider).value ?? const <Member>[])
            .where(
              (m) =>
                  m.active &&
                  m.role != ClubRole.pending &&
                  (m.inTeam(team) || m.id == value),
            )
            .toList()
          ..sort((a, b) {
            final pa = a.fieldPosition == 'POR' ? 0 : 1;
            final pb = b.fieldPosition == 'POR' ? 0 : 1;
            return pa != pb ? pa - pb : a.displayName.compareTo(b.displayName);
          });
    return DropdownButtonFormField<String?>(
      initialValue: members.any((m) => m.id == value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Portiere della partita'),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Dalla formazione pubblicata'),
        ),
        for (final m in members)
          DropdownMenuItem(
            value: m.id,
            child: Text(
              '${m.displayName}${m.fieldPosition == null ? '' : ' (${m.fieldPosition})'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Scelta del torneo (tra quelli della squadra) a cui collegare la partita.
class _TournamentPicker extends ConsumerWidget {
  const _TournamentPicker({
    required this.team,
    required this.value,
    required this.onChanged,
  });
  final Team team;
  final String? value;
  final ValueChanged<Tournament?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = (ref.watch(tournamentsProvider).value ?? const [])
        .where((t) => t.team == team || t.id == value)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String?>(
      initialValue: list.any((t) => t.id == value) ? value : null,
      decoration: const InputDecoration(labelText: 'Torneo (facoltativo)'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Nessuno')),
        for (final t in list)
          DropdownMenuItem(value: t.id, child: Text(t.name)),
      ],
      onChanged: (id) => onChanged(list.where((t) => t.id == id).firstOrNull),
    );
  }
}
