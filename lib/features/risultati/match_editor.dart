import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import 'match.dart';
import 'matches_repository.dart';

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
  late bool _home = widget.match?.home ?? true;
  late DateTime _date = widget.match?.playedAt ?? DateTime.now();
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
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _opponent,
      _competition,
      _for,
      _against,
      _scorers,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_opponent.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Inserisci il nome dell'avversario.")),
      );
      return;
    }
    setState(() => _saving = true);
    final m = ClubMatch(
      id: widget.match?.id ?? '',
      kind: _kind,
      opponent: _opponent.text.trim(),
      playedAt: DateTime(_date.year, _date.month, _date.day, 21, 30),
      competition: _kind == MatchKind.torneo ? _text(_competition) : null,
      home: _home,
      goalsFor: int.tryParse(_for.text),
      goalsAgainst: int.tryParse(_against.text),
      scorers: _text(_scorers),
      notes: _text(_notes),
      team: _team,
    );
    try {
      await ref.read(matchesRepositoryProvider).save(m);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
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
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
            const Center(
              child: Text(
                'Lascia vuoto il punteggio se la partita non è ancora stata giocata.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
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
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note / commento'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: MilanacColors.red),
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
