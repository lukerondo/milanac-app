import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/async_view.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../carte/special_cards_repository.dart';
import '../presenze/evening.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'formation_pdf.dart';
import 'formation_repository.dart';
import 'modules.dart';
import 'pitch_painter.dart';

/// Sezione Formazione: la formazione pubblicata, in sola lettura (anche per il Direttivo,
/// che la prepara e la pubblica con "Modifica").
class FormazionePage extends StatelessWidget {
  const FormazionePage({super.key});

  @override
  Widget build(BuildContext context) => const FormationBoard(editable: false);
}

/// Editor delle formazioni (Sala Direttivo e "Modifica").
class FormationEditorPage extends StatelessWidget {
  const FormationEditorPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Indietro',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text('FORMAZIONI'),
      flexibleSpace: const Align(
        alignment: Alignment.topCenter,
        child: GoldRule(),
      ),
    ),
    body: const ContentWidth(child: FormationBoard(editable: true)),
  );
}

/// Apre l'editor delle formazioni a schermo intero.
void openFormationEditor(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => const FormationEditorPage()));

/// La prossima partita della squadra (per "vs Atletico Virtuale · gio 21:30").
String? _nextMatchLabel(List<ClubEvent> events, Team team, DateTime now) {
  final from = italianClock(now).subtract(const Duration(hours: 3));
  final next =
      events
          .where(
            (e) =>
                e.type.isMatch &&
                e.concerns({team}) &&
                e.startsAt.isAfter(from),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final e = next.firstOrNull;
  if (e == null) return null;
  final headline = matchHeadline(e, team);
  final who = headline.opponent == null
      ? headline.title
      : 'vs ${headline.opponent}';
  return '$who · ${DateFormat('EEE HH:mm', 'it').format(e.startsAt)}';
}

/// "4 giocatori in campo, 7 ruoli all'IA. …"
String formationSummary(int onField, int ai) {
  final players = onField == 1
      ? '1 giocatore in campo'
      : '$onField giocatori in campo';
  final roles = ai == 0
      ? ''
      : ai == 1
      ? ", 1 ruolo all'IA"
      : ", $ai ruoli all'IA";
  return '$players$roles. Chi è in panchina resta a disposizione '
      'per tutta la serata.';
}

/// La squadra mostrata in Formazione, nella sezione e nell'editor: all'apertura quella
/// del giocatore (Milan AC se è in entrambe). "Modifica" apre l'editor sulla stessa
/// squadra e il pulsante del PDF nella barra in alto scarica quella.
final formationTeamProvider = NotifierProvider.autoDispose<FormationTeam, Team>(
  FormationTeam.new,
);

class FormationTeam extends Notifier<Team> {
  @override
  Team build() {
    final mine = ref.read(profileProvider).value?.teams ?? const {Team.milanac};
    return mine.contains(Team.milanac) ? Team.milanac : Team.futuro;
  }

  void select(Team team) => state = team;
}

/// I membri attivi, per id (anche chi è schierato in una squadra che non è la sua).
Map<String, Member> _activeMembers(List<Member> all) => {
  for (final m in all)
    if (m.active && m.role != ClubRole.pending) m.id: m,
};

/// La panchina: i giocatori della squadra non schierati, in ordine di nome.
List<Member> _benchOf(Formation f, Iterable<Member> active) =>
    active
        .where(
          (m) => m.teams.contains(f.team) && !f.players.containsValue(m.id),
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

/// Condivide il PDF di [formation] (campo, titolari e panchina).
void _sharePdf(
  BuildContext context,
  WidgetRef ref,
  Formation formation,
  List<Member> all,
) {
  final members = _activeMembers(all);
  shareFormationPdf(
    context,
    formation: formation,
    members: members,
    bench: _benchOf(formation, members.values),
    specials: ref.read(activeSpecialCardsProvider),
  );
}

/// Pulsante per la barra in alto della sezione Formazione: scarica il PDF della
/// formazione pubblicata della squadra mostrata (spento finché non è pubblicata).
class FormationPdfAction extends ConsumerWidget {
  const FormationPdfAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(formationTeamProvider);
    final formation = ref.watch(formationProvider(team)).value;
    final all = ref.watch(rosaProvider).value;
    final ready = formation != null && formation.isPublished && all != null;
    return IconButton(
      tooltip: 'Scarica il PDF della formazione',
      icon: const Icon(Icons.download_rounded),
      // La barra in alto è scura in tutti e due i temi.
      disabledColor: MilanacColors.ivory.withValues(alpha: .38),
      onPressed: ready
          ? () => _sharePdf(context, ref, formation.publishedView, all)
          : null,
    );
  }
}

class FormationBoard extends ConsumerStatefulWidget {
  const FormationBoard({super.key, required this.editable});

  /// true nell'editor: si modifica la bozza e si pubblica.
  final bool editable;

  @override
  ConsumerState<FormationBoard> createState() => _FormationBoardState();
}

class _FormationBoardState extends ConsumerState<FormationBoard> {
  /// Copia locale modificata dal Direttivo (null = usa quella salvata).
  Formation? _draft;

  /// Squadra mostrata (la stessa nella sezione e nell'editor).
  Team get _team => ref.read(formationTeamProvider);

  /// Salvataggi in coda: uno alla volta, nell'ordine delle modifiche.
  Future<void> _saves = Future.value();

  /// Salvataggi non ancora finiti: intanto "Pubblica" aspetta.
  var _pendingSaves = 0;
  var _publishing = false;

  /// Ultima formazione salvata davvero, per squadra: ci si torna se un salvataggio non
  /// riesce, e il suo id serve alle modifiche fatte mentre la formazione nasceva.
  final _lastSaved = <Team, Formation>{};

  late final AppLifecycleListener _lifecycle;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // La formazione la pubblica il Direttivo da un altro telefono: si rilegge quando l'app
    // torna in primo piano e, per chi la guarda, ogni minuto (anche se la notifica arriva
    // con la pagina già aperta).
    _lifecycle = AppLifecycleListener(onResume: _reload);
    if (!widget.editable) {
      _refresh = Timer.periodic(const Duration(minutes: 1), (_) => _reload());
    }
  }

  /// La scheda Partite resta viva quando si passa a un'altra scheda: tornando a vederla
  /// (anche aprendo la notifica della formazione) si rilegge.
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
    _visible = visible;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _refresh?.cancel();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    // Senza salvataggi in corso la bozza locale lascia il posto a quella del server.
    if (_draft != null && _pendingSaves == 0 && !_publishing) {
      setState(() => _draft = null);
    }
    ref.invalidate(formationProvider);
  }

  /// Mostra subito la modifica e la salva. I salvataggi vanno uno alla volta, nell'ordine
  /// delle modifiche: ognuno salva la formazione intera, quindi vince l'ultima.
  Future<void> _update(Formation f) {
    final repository = ref.read(formationRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _draft = f;
      _pendingSaves++;
    });
    return _saves = _saves.then((_) async {
      try {
        final id = f.id.isNotEmpty ? f.id : _lastSaved[f.team]?.id ?? '';
        final saved = await repository.save(f.copyWith(id: id));
        _lastSaved[f.team] = saved;
        if (mounted && identical(_draft, f)) setState(() => _draft = saved);
      } catch (e) {
        // Si torna all'ultima salvata (null = quella letta dal server).
        if (mounted && identical(_draft, f)) {
          setState(() => _draft = _lastSaved[f.team]);
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
          ),
        );
      } finally {
        _pendingSaves--;
        if (mounted) setState(() {});
        if (_pendingSaves == 0) container.invalidate(formationProvider);
      }
    });
  }

  Future<void> _publish(Team team) async {
    final repository = ref.read(formationRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pubblicare la formazione?'),
        content: Text(
          'Ogni giocatore di ${team.label} riceverà una notifica: '
          'titolare (con il suo ruolo) o panchina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Pubblica'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _publishing = true);
    try {
      // Si pubblica quello che è davvero salvato: prima finiscono i salvataggi in corso
      // (le notifiche leggono i posti dal database).
      await _saves;
      final draft = _draft;
      final f = draft != null && draft.team == team
          ? draft
          : _lastSaved[team] ??
                (mounted ? ref.read(formationProvider(team)).value : null);
      if (f == null) return;
      final published = await repository.publish(f);
      HapticFeedback.heavyImpact();
      _lastSaved[team] = published;
      if (mounted && _team == team) setState(() => _draft = published);
      container.invalidate(formationProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Formazione pubblicata: notifiche inviate ai giocatori.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Pubblicazione non riuscita')),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// Trascinando in giù si rilegge la formazione (senza rete la pagina lo segnala
  /// e continua a riprovare da sola).
  Future<void> _pullToRefresh() async {
    if (_draft != null && _pendingSaves == 0 && !_publishing) {
      setState(() => _draft = null);
    }
    try {
      await ref
          .refresh(formationProvider(_team).future)
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final canEdit = widget.editable && isDirettivo;
    final team = ref.watch(formationTeamProvider);
    final saved = ref.watch(formationProvider(team));
    final rosa = ref.watch(rosaProvider);
    final now = ref.watch(clockProvider)();
    final today = italianDay(now);
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];
    final draft = _draft;
    final shown = draft != null && draft.team == team ? draft : saved.value;

    void retry() {
      ref.invalidate(formationProvider(team));
      ref.invalidate(rosaProvider);
    }

    return Column(
      children: [
        _Band(
          team: team,
          onTeam: (t) {
            setState(() => _draft = null);
            ref.read(formationTeamProvider.notifier).select(t);
          },
          status: _StatusRow(
            formation: shown,
            today: today,
            forPlayers: !canEdit,
            nextMatch: _nextMatchLabel(events, team, now),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _pullToRefresh,
            child: AsyncView(
              value: saved,
              onRetry: retry,
              data: (savedFormation) => AsyncView(
                value: rosa,
                onRetry: retry,
                data: (all) => _board(
                  canEdit: canEdit,
                  isDirettivo: isDirettivo,
                  savedFormation: savedFormation,
                  all: all,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _board({
    required bool canEdit,
    required bool isDirettivo,
    required Formation savedFormation,
    required List<Member> all,
  }) {
    final p = context.pal;
    final draft = _draft;
    final current = draft != null && draft.team == _team
        ? draft
        : savedFormation;
    // I giocatori vedono la versione pubblicata, il Direttivo (nell'editor) la bozza.
    final formation = canEdit ? current : current.publishedView;
    // Tutti i membri (per mostrare chi è già schierato) e quelli della squadra (per le scelte).
    final allMembers = _activeMembers(all);
    final members = {
      for (final m in allMembers.values)
        if (m.teams.contains(_team)) m.id: m,
    };
    final bench = _benchOf(formation, allMembers.values);
    final onField = [
      for (final (i, _) in formation.slots.indexed)
        if (allMembers.containsKey(formation.players[i])) i,
    ].length;

    void sharePdf() => _sharePdf(context, ref, formation, all);

    final buttonText = const TextStyle(
      fontFamily: bodyFont,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );

    return ListView(
      // Si trascina in giù per rileggere anche quando la pagina è quasi vuota.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        if (!canEdit && !current.isPublished)
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
            child: Column(
              children: [
                Icon(
                  Icons.hourglass_empty_rounded,
                  size: 40,
                  color: p.textMuted,
                ),
                const SizedBox(height: 10),
                Text(
                  'La formazione di ${_team.label} non è ancora stata pubblicata.\n'
                  'Arriverà una notifica quando il Direttivo la pubblica.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 15),
                ),
                if (isDirettivo) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => openFormationEditor(context),
                    child: const Text('Prepara la formazione'),
                  ),
                ],
              ],
            ),
          )
        else ...[
          if (canEdit) ...[
            const SectionLabel('Modulo'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final module in formationModules.keys)
                  FilterPill(
                    label: module,
                    selected: formation.module == module,
                    onTap: () {
                      if (formation.module != module) {
                        _update(formation.copyWith(module: module));
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Semantics(
            label:
                'Campo con la formazione ${formation.module}: '
                '${formationSummary(onField, formation.slots.length - onField)}',
            child: AspectRatio(
              aspectRatio: .81,
              child: LayoutBuilder(
                builder: (context, box) {
                  const inset = PitchPainter.inset;
                  final fieldW = box.maxWidth - inset * 2;
                  final fieldH = box.maxHeight - inset * 2;
                  return Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: PitchPainter()),
                      ),
                      // Foto e nome insieme sono centrati sul posto: così anche
                      // il portiere resta dentro il campo.
                      for (final (i, slot) in formation.slots.indexed)
                        Positioned(
                          left: inset + slot.x * fieldW - 40,
                          top: inset + slot.y * fieldH - 31,
                          width: 80,
                          child: _PlayerToken(
                            slot: slot,
                            member: allMembers[formation.players[i]],
                            onTap: canEdit
                                ? () async {
                                    final choice = await _pickPlayer(
                                      context,
                                      slot: slot,
                                      current: allMembers[formation.players[i]],
                                      members: members.values.toList(),
                                      formation: formation,
                                    );
                                    if (choice == null) return;
                                    await _update(
                                      formation.assign(
                                        i,
                                        choice.isEmpty ? null : choice,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            formationSummary(onField, formation.slots.length - onField),
            style: TextStyle(color: p.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (canEdit) ...[
            Text(
              'Tocca un posto per scegliere il giocatore. Le modifiche restano '
              'in bozza finché non pubblichi.',
              style: TextStyle(color: p.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 12),
            // Si pubblica solo a salvataggio finito: le notifiche leggono i posti salvati.
            FilledButton.icon(
              onPressed: _pendingSaves > 0 || _publishing
                  ? null
                  : () => _publish(formation.team),
              icon: _pendingSaves > 0 || _publishing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_rounded),
              label: Text(
                _pendingSaves > 0
                    ? 'Salvataggio in corso…'
                    : _publishing
                    ? 'Pubblicazione in corso…'
                    : formation.isPublished && !formation.hasUnpublishedChanges
                    ? 'Ripubblica e avvisa i giocatori'
                    : 'Pubblica la formazione di stasera',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(textStyle: buttonText),
              onPressed: sharePdf,
              child: const Text('Condividi PDF'),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(textStyle: buttonText),
                    onPressed: sharePdf,
                    child: const Text('Condividi PDF'),
                  ),
                ),
                if (isDirettivo) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(textStyle: buttonText),
                      onPressed: () => openFormationEditor(context),
                      child: const Text('Modifica'),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 22),
          const SectionLabel('Panchina'),
          const SizedBox(height: 8),
          if (bench.isEmpty)
            Text(
              'Tutti i giocatori sono in campo.',
              style: TextStyle(color: p.textMuted, fontSize: 15),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final m in bench) _BenchPill(member: m)],
            ),
        ],
      ],
    );
  }
}

/// La fascia in alto: Milan AC | Futuro e lo stato della formazione.
class _Band extends StatelessWidget {
  const _Band({required this.team, required this.onTeam, required this.status});
  final Team team;
  final ValueChanged<Team> onTeam;
  final Widget status;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedTabs(
              labels: [for (final t in Team.values) teamTabLabel(t)],
              selected: Team.values.indexOf(team),
              onSelected: (i) => onTeam(Team.values[i]),
            ),
            status,
          ],
        ),
      ),
    );
  }
}

/// Stato della formazione (bozza, pubblicata, modificata), modulo e prossima partita.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.formation,
    required this.today,
    required this.forPlayers,
    required this.nextMatch,
  });

  /// null = non ancora caricata.
  final Formation? formation;

  /// Oggi in Italia.
  final DateTime today;

  /// Vista dei giocatori: niente "bozza" o "modificata", solo quando è stata pubblicata.
  final bool forPlayers;
  final String? nextMatch;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = formation;
    // Giorno della pubblicazione in ora italiana.
    final published = f?.publishedAt == null
        ? null
        : italianClock(f!.publishedAt!);
    final (String, Color, Color)? state = f == null
        ? null
        : published == null
        ? forPlayers
              ? null
              : ('Bozza, non pubblicata', p.textSecondary, p.surfaceHigh)
        : f.hasUnpublishedChanges && !forPlayers
        ? ('Modificata dopo la pubblicazione', p.warning, p.warningBg)
        : (
            f.isPublishedOn(today)
                ? 'Pubblicata oggi'
                : 'Pubblicata il ${DateFormat('d MMM', 'it').format(published)}',
            p.success,
            p.successBg,
          );
    final module = f == null
        ? null
        : forPlayers
        ? (f.isPublished ? f.publishedView.module : null)
        : f.module;
    final children = [
      if (state != null)
        _StatusPill(label: state.$1, color: state.$2, background: state.$3),
      if (module != null)
        _StatusPill(
          label: module,
          color: p.text,
          background: p.surfaceHigh,
          border: p.borderStrong,
        ),
      if (nextMatch != null)
        Text(
          nextMatch!,
          style: TextStyle(color: p.textSecondary, fontSize: 14),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
    this.border,
  });
  final String label;
  final Color color;
  final Color background;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
      border: border == null ? null : Border.all(color: border!),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
}

/// Un giocatore in panchina.
class _BenchPill extends StatelessWidget {
  const _BenchPill({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MemberAvatar(member: member, radius: 14, showNumber: false),
          const SizedBox(width: 8),
          Text(
            [
              member.displayName,
              if (member.fieldPosition != null) member.fieldPosition!,
            ].join(' · '),
            style: TextStyle(
              color: p.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Restituisce l'id del giocatore scelto, '' per liberare la posizione, null se annullato.
Future<String?> _pickPlayer(
  BuildContext context, {
  required SlotPosition slot,
  required Member? current,
  required List<Member> members,
  required Formation formation,
}) {
  // Prima chi gioca in quel ruolo, poi gli altri.
  final sorted = List.of(members)
    ..sort((a, b) {
      final ra = a.fieldPosition == slot.label ? 0 : 1;
      final rb = b.fieldPosition == slot.label ? 0 : 1;
      return ra != rb ? ra - rb : a.displayName.compareTo(b.displayName);
    });

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) {
      final p = c.pal;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .9,
        builder: (c, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'CHI GIOCA ${slot.label}?',
                style: TextStyle(
                  fontFamily: sportFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  letterSpacing: .5,
                  color: p.text,
                ),
              ),
            ),
            if (current != null)
              ListTile(
                leading: Icon(Icons.person_remove_rounded, color: p.danger),
                title: const Text('Libera la posizione'),
                subtitle: const Text("Il ruolo passa all'IA"),
                onTap: () => Navigator.pop(c, ''),
              ),
            for (final m in sorted)
              ListTile(
                leading: MemberAvatar(member: m, radius: 20),
                title: Text(
                  m.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    if (m.fieldPosition != null) m.fieldPosition!,
                    if (formation.players.containsValue(m.id))
                      'già in campo: verrà spostato',
                  ].join(' · '),
                ),
                trailing: m.fieldPosition == slot.label
                    ? Icon(Icons.star_rounded, color: p.accentText)
                    : null,
                selected: m.id == current?.id,
                onTap: () => Navigator.pop(c, m.id),
              ),
          ],
        ),
      );
    },
  );
}

/// Un posto in campo: la foto con il bordo oro e "9 Rossi", oppure (posto libero) il
/// cerchio tratteggiato dell'IA con il ruolo. Il campo è scuro anche nel tema chiaro.
class _PlayerToken extends StatelessWidget {
  const _PlayerToken({required this.slot, required this.member, this.onTap});
  final SlotPosition slot;
  final Member? member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final label = m == null
        ? slot.label
        : [
            if (m.shirtNumber != null) '${m.shirtNumber}',
            m.displayName.split(' ').last,
          ].join(' ');
    return Semantics(
      button: onTap != null,
      label: m == null
          ? "${slot.label}: ruolo all'IA"
          : '${slot.label}: ${m.displayName}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 44,
              child: m == null
                  ? const CustomPaint(
                      painter: _DashedCircle(),
                      child: Center(
                        child: Text(
                          'IA',
                          style: TextStyle(
                            fontFamily: sportFont,
                            fontSize: 14,
                            color: MilanacColors.ivory,
                          ),
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: const BoxDecoration(
                        color: MilanacColors.gold,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: MemberAvatar(
                          member: m,
                          radius: 20,
                          showNumber: false,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MilanacColors.ivory,
                shadows: [Shadow(color: MilanacColors.black, blurRadius: 3)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cerchio tratteggiato di un posto lasciato all'IA.
class _DashedCircle extends CustomPainter {
  const _DashedCircle();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = MilanacColors.ink.withValues(alpha: .4),
    );
    final dash = Paint()
      ..color = MilanacColors.ivory.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const segments = 16;
    const sweep = 2 * 3.141592653589793 / segments;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * .55, false, dash);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCircle oldDelegate) => false;
}
