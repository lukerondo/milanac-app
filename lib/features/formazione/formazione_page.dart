import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'formation_repository.dart';
import 'modules.dart';
import 'pitch_painter.dart';

/// Sezione Formazione: la formazione pubblicata, in sola lettura (anche per il Direttivo,
/// che la prepara e la pubblica dalla Sala Direttivo).
class FormazionePage extends StatelessWidget {
  const FormazionePage({super.key});

  @override
  Widget build(BuildContext context) => const FormationBoard(editable: false);
}

/// Editor delle formazioni nella Sala Direttivo.
class FormationEditorPage extends StatelessWidget {
  const FormationEditorPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FORMAZIONI')),
    body: const FormationBoard(editable: true),
  );
}

class FormationBoard extends ConsumerStatefulWidget {
  const FormationBoard({super.key, required this.editable});

  /// true nella Sala Direttivo: si modifica la bozza e si pubblica.
  final bool editable;

  @override
  ConsumerState<FormationBoard> createState() => _FormationBoardState();
}

class _FormationBoardState extends ConsumerState<FormationBoard> {
  /// Copia locale modificata dal Direttivo (null = usa quella salvata).
  Formation? _draft;

  /// Squadra mostrata: all'apertura quella del giocatore (MILANAC se è in entrambe).
  late Team _team = () {
    final mine = ref.read(profileProvider).value?.teams ?? const {Team.milanac};
    return mine.contains(Team.milanac) ? Team.milanac : Team.futuro;
  }();

  Future<void> _update(Formation f) async {
    final previous = _draft;
    setState(() => _draft = f);
    try {
      final saved = await ref.read(formationRepositoryProvider).save(f);
      if (mounted) setState(() => _draft = saved);
      ref.invalidate(formationProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _draft = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  Future<void> _publish(Formation f) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pubblicare la formazione?'),
        content: Text(
          'Ogni giocatore di ${f.team.label} riceverà una notifica: '
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
    if (ok != true) return;
    try {
      final published = await ref.read(formationRepositoryProvider).publish(f);
      if (mounted) setState(() => _draft = published);
      ref.invalidate(formationProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Formazione pubblicata: notifiche inviate ai giocatori.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Pubblicazione non riuscita: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final canEdit = widget.editable && isDirettivo;
    final saved = ref.watch(formationProvider(_team));
    final rosa = ref.watch(rosaProvider);

    if (saved.isLoading || rosa.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (saved.hasError || rosa.hasError) {
      return Center(
        child: Text('Errore nel caricamento: ${saved.error ?? rosa.error}'),
      );
    }

    final draft = _draft;
    final current = draft != null && draft.team == _team ? draft : saved.value!;
    // I giocatori vedono la versione pubblicata, il Direttivo (in sala) la bozza.
    final formation = canEdit ? current : current.publishedView;
    // Tutti i membri (per mostrare chi è già schierato) e quelli della squadra (per le scelte).
    final allMembers = {
      for (final m in rosa.value!)
        if (m.active && m.role != ClubRole.pending) m.id: m,
    };
    final members = {
      for (final m in allMembers.values)
        if (m.teams.contains(_team)) m.id: m,
    };
    final bench =
        members.values
            .where((m) => !formation.players.containsValue(m.id))
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        SegmentedButton<Team>(
          segments: [
            for (final t in Team.values)
              ButtonSegment(value: t, label: Text(t.short)),
          ],
          selected: {_team},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _team = s.first;
            _draft = null;
          }),
        ),
        const SizedBox(height: 10),
        _PublishStatus(formation: current, forPlayers: !canEdit),
        if (!canEdit && !current.isPublished) ...[
          const SizedBox(height: 40),
          const Icon(
            Icons.hourglass_empty_rounded,
            size: 48,
            color: Colors.white38,
          ),
          const SizedBox(height: 8),
          Text(
            'La formazione di ${_team.label} non è ancora stata pubblicata.\n'
            'Arriverà una notifica quando il Direttivo la pubblica.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          if (isDirettivo) ...[const SizedBox(height: 16), _OpenEditorButton()],
        ] else ...[
          const SizedBox(height: 8),
          if (!canEdit)
            Center(
              child: Chip(
                label: Text(
                  formation.module,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final module in formationModules.keys)
                  ChoiceChip(
                    label: Text(
                      module,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    selected: formation.module == module,
                    // Sempre attivo (solo il Direttivo può davvero cambiare modulo),
                    // così il modulo corrente non appare "disabilitato".
                    onSelected: (_) {
                      if (canEdit && formation.module != module) {
                        _update(formation.copyWith(module: module));
                      }
                    },
                  ),
              ],
            ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 0.68,
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
                    for (final (i, slot) in formation.slots.indexed)
                      Positioned(
                        left: inset + slot.x * fieldW - 40,
                        top: inset + slot.y * fieldH - 28,
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
          if (!canEdit && isDirettivo) ...[
            const SizedBox(height: 12),
            _OpenEditorButton(),
          ],
          if (canEdit) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Tocca un bollino per scegliere il giocatore. Le modifiche restano in bozza '
                'finché non pubblichi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _publish(formation),
              icon: const Icon(Icons.campaign_rounded),
              label: Text(
                formation.isPublished && !formation.hasUnpublishedChanges
                    ? 'Ripubblica e avvisa i giocatori'
                    : 'Pubblica la formazione di stasera',
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text(
              'PANCHINA',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
          ),
          if (bench.isEmpty)
            const Padding(
              padding: EdgeInsets.all(4),
              child: Text(
                'Tutti i giocatori sono in campo.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in bench)
                Chip(
                  avatar: CircleAvatar(
                    backgroundColor: MilanacColors.redDark,
                    child: Text(
                      m.shirtNumber?.toString() ?? '–',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  label: Text(
                    '${m.displayName}${m.fieldPosition != null ? ' · ${m.fieldPosition}' : ''}',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Per il Direttivo: apre l'editor delle formazioni (Sala Direttivo).
class _OpenEditorButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: OutlinedButton.icon(
      onPressed: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => const FormationEditorPage())),
      icon: const Icon(Icons.admin_panel_settings_rounded),
      label: const Text('Prepara e pubblica nella Sala Direttivo'),
    ),
  );
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
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .9,
      builder: (c, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Chi gioca ${slot.label}?',
              style: Theme.of(c).textTheme.titleLarge,
            ),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.person_remove_rounded),
              title: const Text('Libera la posizione'),
              onTap: () => Navigator.pop(c, ''),
            ),
          for (final m in sorted)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: MilanacColors.red,
                child: Text(
                  m.shirtNumber?.toString() ?? '–',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(m.displayName),
              subtitle: Text(
                [
                  if (m.fieldPosition != null) m.fieldPosition!,
                  if (formation.players.containsValue(m.id))
                    'già in campo: verrà spostato',
                ].join(' · '),
              ),
              trailing: m.fieldPosition == slot.label
                  ? const Icon(Icons.star_rounded, color: MilanacColors.gold)
                  : null,
              selected: m.id == current?.id,
              onTap: () => Navigator.pop(c, m.id),
            ),
        ],
      ),
    ),
  );
}

class _PlayerToken extends StatelessWidget {
  const _PlayerToken({required this.slot, required this.member, this.onTap});
  final SlotPosition slot;
  final Member? member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filled = member != null;
    final isKeeper = slot.label == 'POR';
    final surname = filled ? member!.displayName.split(' ').last : slot.label;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !filled
                  ? Colors.black.withValues(alpha: .35)
                  : isKeeper
                  ? MilanacColors.gold
                  : MilanacColors.red,
              border: Border.all(
                color: filled ? Colors.white : Colors.white70,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: filled
                ? Text(
                    member!.shirtNumber?.toString() ?? surname[0],
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: isKeeper ? Colors.black : Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: Colors.white70,
                  ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              surname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stato della formazione: bozza, pubblicata, oppure modificata dopo la pubblicazione.
class _PublishStatus extends StatelessWidget {
  const _PublishStatus({required this.formation, this.forPlayers = false});
  final Formation formation;

  /// Vista dei giocatori: niente "bozza" o "modificata", solo quando è stata pubblicata.
  final bool forPlayers;

  @override
  Widget build(BuildContext context) {
    if (forPlayers && !formation.isPublished) return const SizedBox.shrink();
    final (icon, color, text) = !formation.isPublished
        ? (
            Icons.edit_note_rounded,
            Colors.white54,
            'Bozza: non ancora pubblicata',
          )
        : formation.hasUnpublishedChanges && !forPlayers
        ? (
            Icons.warning_amber_rounded,
            MilanacColors.gold,
            'Modificata dopo la pubblicazione: ripubblica per avvisare i giocatori',
          )
        : (
            Icons.verified_rounded,
            const Color(0xFF2E9E5B),
            'Pubblicata ${formation.isPublishedToday ? 'oggi' : 'il ${DateFormat('d MMM', 'it').format(formation.publishedAt!.toLocal())}'}'
                ' alle ${DateFormat('HH:mm').format(formation.publishedAt!.toLocal())}',
          );
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}
