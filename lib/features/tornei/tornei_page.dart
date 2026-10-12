import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import '../risultati/matches_repository.dart';
import '../risultati/result_ui.dart';
import '../risultati/risultati_page.dart' show MatchList;
import 'tournaments_repository.dart';

/// Tornei del club (scheda di Partite): una card per torneo con stato, classifica
/// (per quelli in corso) e link al sito dell'organizzatore, come la tavola.
class TorneiPage extends ConsumerWidget {
  const TorneiPage({super.key});

  static const _order = [
    TournamentStatus.inCorso,
    TournamentStatus.iscrizioni,
    TournamentStatus.concluso,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final tournaments = ref.watch(tournamentsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              onPressed: () => showTournamentEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuovo torneo'),
            )
          : null,
      body: AsyncView(
        value: tournaments,
        onRetry: () => ref.invalidate(tournamentsProvider),
        data: (all) {
          final current =
              all.where((t) => t.status != TournamentStatus.concluso).toList()
                ..sort(
                  (a, b) => _order
                      .indexOf(a.status)
                      .compareTo(_order.indexOf(b.status)),
                );
          final done = all
              .where((t) => t.status == TournamentStatus.concluso)
              .toList();
          return RefreshIndicator(
            onRefresh: () => _refreshStandings(ref, current),
            child: ListView(
              // Si trascina in giù anche con pochi tornei.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (all.isEmpty)
                  AppCard(
                    child: Text(
                      'Nessun torneo registrato.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: context.pal.textMuted,
                      ),
                    ),
                  ),
                for (final t in current)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _TournamentCard(tournament: t),
                  ),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const SectionLabel('Conclusi'),
                  const SizedBox(height: 10),
                  for (final t in done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _TournamentCard(tournament: t),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Le classifiche non arrivano in tempo reale: trascinando in giù si rileggono (senza
  /// rete la pagina lo segnala e continua a riprovare da sola).
  static Future<void> _refreshStandings(
    WidgetRef ref,
    List<Tournament> shown,
  ) async {
    // Si aspettano le classifiche mostrate (quelle dei tornei in corso).
    final visible = [
      for (final t in shown)
        if (t.status == TournamentStatus.inCorso &&
            ref.exists(standingsProvider(t.id)))
          standingsProvider(t.id),
    ];
    ref.invalidate(standingsProvider);
    try {
      await Future.wait([for (final p in visible) ref.read(p.future)])
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}

/// "Milan AC · in corso dal 15 settembre", "Milan AC Futuro · Torneo amatoriale".
String _subtitle(Tournament t) {
  String day(DateTime d) => DateFormat('d MMMM', 'it').format(d);
  final detail = switch (t.status) {
    TournamentStatus.inCorso when t.startsOn != null =>
      'in corso dal ${day(t.startsOn!)}',
    TournamentStatus.iscrizioni when t.startsOn != null =>
      'inizia il ${day(t.startsOn!)}',
    TournamentStatus.concluso when t.endsOn != null =>
      'concluso il ${day(t.endsOn!)}',
    _ => t.organizer,
  };
  return [t.team.label, ?detail].join(' · ');
}

/// Pillola dello stato: in corso (verde), iscrizioni (ambra), concluso (grigio).
Widget _statusPill(BuildContext context, TournamentStatus s) {
  final p = context.pal;
  final (text, fg, bg) = switch (s) {
    TournamentStatus.inCorso => ('In corso', p.success, p.successBg),
    TournamentStatus.iscrizioni => ('Iscrizioni', p.warning, p.warningBg),
    TournamentStatus.concluso => ('Concluso', p.textSecondary, p.surfaceHigh),
  };
  return StatusPill(text, color: fg, background: bg);
}

/// Sigla del torneo per il riquadro senza logo ("FVPA Serie B" → "FVPA",
/// "Coppa Riserve" → "CR").
String tournamentInitials(String name) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  final acronym =
      first.length >= 2 &&
      first.length <= 5 &&
      first == first.toUpperCase() &&
      first.contains(RegExp(r'[A-Z]'));
  return acronym ? first : initialsOf(name);
}

class _TournamentCard extends ConsumerWidget {
  const _TournamentCard({required this.tournament});
  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final t = tournament;
    final live = t.status == TournamentStatus.inCorso;
    final standings = live
        ? ref.watch(standingsProvider(t.id)).value ?? const <StandingRow>[]
        : const <StandingRow>[];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => TournamentPage(tournamentId: t.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  TournamentTile(tournament: t, highlighted: live),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: sportFont,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .6,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          _subtitle(t),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusPill(context, t.status),
                ],
              ),
            ),
          ),
          if (standings.isNotEmpty) StandingsTable(rows: standings),
          if (t.url != null) ...[
            const Divider(),
            InkWell(
              onTap: () => _open(t.url!),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Sito del torneo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.accentText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: p.accentText,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _open(String url) => openExternalLink(url);

/// Riquadro del torneo: il logo caricato o la sigla; in evidenza (oro) se è in corso.
class TournamentTile extends ConsumerWidget {
  const TournamentTile({
    super.key,
    required this.tournament,
    this.highlighted = false,
    this.size = 52,
  });
  final Tournament tournament;
  final bool highlighted;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final path = tournament.imagePath;
    final image = path == null
        ? null
        : ref.watch(tournamentImageProvider(path)).value;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: highlighted ? p.accentTint : p.surfaceHigh,
        borderRadius: BorderRadius.circular(size * .23),
        border: highlighted ? Border.all(color: p.importantBorder) : null,
      ),
      child: image != null
          ? Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          : Padding(
              padding: const EdgeInsets.all(4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tournamentInitials(tournament.name),
                  style: TextStyle(
                    fontFamily: sportFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .6,
                    color: highlighted ? p.accentText : p.text,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Foto o logo del torneo in tondo (icona della coppa se manca).
class TournamentLogo extends ConsumerWidget {
  const TournamentLogo({super.key, required this.tournament, this.radius = 22});
  final Tournament tournament;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final path = tournament.imagePath;
    final image = path == null
        ? null
        : ref.watch(tournamentImageProvider(path)).value;
    return CircleAvatar(
      radius: radius,
      backgroundColor: p.surfaceHigh,
      backgroundImage: image,
      child: image == null
          ? Icon(Icons.emoji_events_rounded, color: p.accentText, size: radius)
          : null,
    );
  }
}

/// La foto del torneo in grande, nel dettaglio.
class _TournamentPhoto extends ConsumerWidget {
  const _TournamentPhoto({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(tournamentImageProvider(path)).value;
    if (image == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image(
          image: image,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Dettaglio: info, sito, classifica e partite del torneo.
class TournamentPage extends ConsumerStatefulWidget {
  const TournamentPage({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends ConsumerState<TournamentPage> {
  @override
  void initState() {
    super.initState();
    // La card dei Tornei tiene la classifica in memoria: aprendo il torneo si rilegge
    // (intanto si vede quella di prima).
    final standings = standingsProvider(widget.tournamentId);
    if (ref.exists(standings)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(standings);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournamentId = widget.tournamentId;
    final p = context.pal;
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final tournaments = ref.watch(tournamentsProvider);
    final t = tournaments.value?.where((x) => x.id == tournamentId).firstOrNull;
    final standings = ref.watch(standingsProvider(tournamentId));
    final matches = (ref.watch(matchesProvider).value ?? const [])
        .where((m) => m.tournamentId == tournamentId)
        .toList();
    final dates = DateFormat('d MMMM yyyy', 'it');

    return Scaffold(
      appBar: AppBar(
        title: const Text('TORNEO'),
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
        actions: [
          if (isDirettivo && t != null)
            IconButton(
              tooltip: 'Modifica torneo',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => showTournamentEditor(context, tournament: t),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: t == null
          // Lo spinner finché l'elenco non è caricato; poi, se il torneo non c'è
          // più (eliminato da un altro telefono), lo si dice.
          ? tournaments.hasError &&
                    (!tournaments.isLoading || tournaments.retrying)
                ? ErrorRetry(
                    message: friendlyError(
                      tournaments.error!,
                      action: 'Caricamento non riuscito',
                    ),
                    onRetry: () => ref.invalidate(tournamentsProvider),
                  )
                : tournaments.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ErrorRetry(
                    message: 'Torneo non trovato.',
                    onRetry: () => ref.invalidate(tournamentsProvider),
                  )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (t.imagePath != null) _TournamentPhoto(path: t.imagePath!),
                AppCard(
                  important: t.status == TournamentStatus.inCorso,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TournamentTile(
                            tournament: t,
                            highlighted: t.status == TournamentStatus.inCorso,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.name.toUpperCase(),
                                  style: const TextStyle(
                                    fontFamily: sportFont,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: .6,
                                    height: 1.15,
                                  ),
                                ),
                                Text(
                                  t.team.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: p.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _statusPill(context, t.status),
                      ),
                      if (t.organizer != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Organizzatore: ${t.organizer}',
                          style: TextStyle(fontSize: 14, color: p.textMuted),
                        ),
                      ],
                      if (t.startsOn != null)
                        Text(
                          t.endsOn == null
                              ? 'Dal ${dates.format(t.startsOn!)}'
                              : 'Dal ${dates.format(t.startsOn!)} al ${dates.format(t.endsOn!)}',
                          style: TextStyle(fontSize: 14, color: p.textMuted),
                        ),
                      if (t.notes != null && t.notes!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          t.notes!,
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                if (t.url != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _open(t.url!),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Apri il sito del torneo'),
                  ),
                ],
                const SizedBox(height: 22),
                SectionLabel(
                  'Classifica',
                  trailing: isDirettivo
                      ? TextButton.icon(
                          // Solo con la classifica appena caricata: partire da un
                          // elenco vuoto (o vecchio, mentre si rilegge) e salvare la
                          // cancellerebbe.
                          onPressed: standings.hasValue && !standings.isLoading
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StandingsEditorPage(
                                      tournamentId: t.id,
                                      initial: standings.requireValue,
                                    ),
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.edit_note_rounded),
                          label: const Text('Aggiorna'),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                AsyncView(
                  value: standings,
                  onRetry: () => ref.invalidate(standingsProvider(t.id)),
                  loading: const LinearProgressIndicator(),
                  data: (rows) => rows.isNotEmpty
                      ? AppCard(
                          padding: EdgeInsets.zero,
                          child: StandingsTable(rows: rows),
                        )
                      : Text(
                          'Classifica non inserita: si trova sul sito del torneo.',
                          style: TextStyle(fontSize: 15, color: p.textMuted),
                        ),
                ),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const SectionLabel('Partite'),
                  const SizedBox(height: 10),
                  MatchList(matches: matches),
                ],
              ],
            ),
    );
  }
}

/// Classifica come nella tavola: #, squadra, G, V, N, P, gol fatti:subiti e punti;
/// la nostra riga in evidenza.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.rows});
  final List<StandingRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const numbers = [FontFeature.tabularFigures()];
    final head = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: p.textMuted,
    );
    Widget cell(String text, {TextStyle? style, double width = 30}) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, maxLines: 1, style: style),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: p.surfaceHigh,
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              SizedBox(width: 28, child: Text('#', style: head)),
              Expanded(child: Text('Squadra', style: head)),
              for (final h in ['G', 'V', 'N', 'P']) cell(h, style: head),
              cell('Gol', style: head, width: 44),
              cell('Pt', style: head, width: 44),
            ],
          ),
        ),
        for (final (i, r) in rows.indexed)
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            decoration: BoxDecoration(
              color: r.isUs ? p.accentTint : null,
              border: i == 0 ? null : Border(top: BorderSide(color: p.divider)),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 15,
                fontWeight: r.isUs ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: numbers,
                color: p.text,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: r.isUs ? p.accentText : null),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: r.isUs ? p.accentText : null),
                    ),
                  ),
                  for (final v in [r.played, r.won, r.drawn, r.lost])
                    cell('$v'),
                  cell('${r.goalsFor}:${r.goalsAgainst}', width: 44),
                  cell(
                    '${r.points}',
                    width: 44,
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: r.isUs ? p.accentText : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
  late DateTime? _endsOn = widget.tournament?.endsOn;
  Uint8List? _photo;
  bool _saving = false;

  /// Il torneo nuovo creato da un salvataggio rimasto a metà (la foto non è partita):
  /// "Salva" di nuovo lo aggiorna invece di crearne un doppione.
  String? _createdId;

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Foto non caricata'))),
      );
    }
  }

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
    final startsOn = _startsOn;
    final endsOn = _endsOn;
    final error =
        _text(_name) == null ||
            (url != null && Uri.tryParse(url)?.host.isNotEmpty != true)
        ? 'Inserisci il nome e un link valido.'
        : startsOn != null && endsOn != null && endsOn.isBefore(startsOn)
        ? 'La data di fine viene prima di quella di inizio.'
        : null;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    final old = widget.tournament;
    final t = Tournament(
      id: _createdId ?? old?.id ?? '',
      name: _text(_name)!,
      organizer: _text(_organizer),
      url: url,
      team: _team,
      status: _status,
      startsOn: startsOn,
      endsOn: endsOn,
      notes: _text(_notes),
      imagePath: old?.imagePath,
    );
    try {
      final repo = ref.read(tournamentsRepositoryProvider);
      final id = await repo.save(t);
      _createdId = id;
      final photo = _photo;
      if (photo != null) {
        // La foto di prima si toglie solo a foto nuova collegata.
        await repo.uploadImage(id, photo, replacing: old?.imagePath);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
        ),
      );
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
    setState(() => _saving = true);
    try {
      await ref
          .read(tournamentsRepositoryProvider)
          .delete(widget.tournament!.id);
      nav
        ..pop()
        ..pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Eliminazione non riuscita')),
        ),
      );
    }
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
            // I limiti sono quelli della tabella `tournaments`.
            TextField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Nome del torneo',
                hintText: 'es. FVPA Serie B',
              ),
            ),
            TextField(
              controller: _organizer,
              maxLength: 60,
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
            _DateTile(
              label: 'Inizio',
              empty: 'Data di inizio (facoltativa)',
              value: _startsOn,
              onChanged: (d) => setState(() => _startsOn = d),
            ),
            _DateTile(
              label: 'Fine',
              empty: 'Data di fine (facoltativa)',
              value: _endsOn,
              onChanged: (d) => setState(() => _endsOn = d),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Note (facoltative)',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _photo!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (widget.tournament != null)
                  TournamentLogo(tournament: widget.tournament!, radius: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickPhoto,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: Text(
                      _photo != null || widget.tournament?.imagePath != null
                          ? 'Cambia foto o logo'
                          : 'Foto o logo del torneo',
                    ),
                  ),
                ),
              ],
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
                child: Text(
                  'Elimina torneo',
                  style: TextStyle(color: context.pal.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una data facoltativa del torneo: si sceglie toccandola e si toglie con la crocetta.
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.empty,
    required this.value,
    required this.onChanged,
  });
  final String label;

  /// Il testo quando la data non c'è.
  final String empty;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final day = value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_rounded),
      title: Text(
        day == null
            ? empty
            : '$label: ${DateFormat('d MMMM yyyy', 'it').format(day)}',
      ),
      trailing: day == null
          ? null
          : IconButton(
              tooltip: 'Togli la data (${label.toLowerCase()})',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => onChanged(null),
            ),
      onTap: () async {
        final first = DateTime(2020);
        final last = DateTime(DateTime.now().year + 2, 12, 31);
        // Una data salvata fuori dai limiti del calendario non lo blocca.
        var initial = day ?? DateTime.now();
        if (initial.isBefore(first)) initial = first;
        if (initial.isAfter(last)) initial = last;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: last,
        );
        if (picked != null) onChanged(picked);
      },
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CLASSIFICA'),
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
        actions: [
          // La barra è sempre scura: l'oro chiaro si legge in tutti e due i temi.
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: MilanacColors.goldLight,
            ),
            onPressed: _saving ? null : _save,
            child: const Text('SALVA'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Aggiungi squadra'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            'Punti e partite giocate si calcolano da vittorie, pareggi e sconfitte. '
            "Tocca una riga per modificarla, tieni premuto per toglierla.",
            style: TextStyle(fontSize: 15, color: context.pal.textMuted),
          ),
          const SizedBox(height: 12),
          if (_rows.isNotEmpty) ...[
            AppCard(
              padding: EdgeInsets.zero,
              child: StandingsTable(rows: sortStandings(_rows)),
            ),
            const SizedBox(height: 8),
          ],
          for (final (i, r) in _rows.indexed)
            ListTile(
              title: Text(r.teamName),
              subtitle: Text(
                'V ${r.won} · N ${r.drawn} · P ${r.lost} · Gol ${r.goalsFor}-${r.goalsAgainst}',
              ),
              trailing: r.isUs
                  ? Icon(Icons.star_rounded, color: context.pal.accentText)
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
          // I limiti sono quelli della tabella `tournament_standings`.
          TextField(
            controller: _name,
            maxLength: 60,
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
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
