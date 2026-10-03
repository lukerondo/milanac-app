import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'formation_repository.dart';
import 'modules.dart';
import 'pitch_painter.dart';

class FormazionePage extends ConsumerStatefulWidget {
  const FormazionePage({super.key});

  @override
  ConsumerState<FormazionePage> createState() => _FormazionePageState();
}

class _FormazionePageState extends ConsumerState<FormazionePage> {
  /// Copia locale modificata dal Direttivo (null = usa quella salvata).
  Formation? _draft;

  Future<void> _update(Formation f) async {
    final previous = _draft;
    setState(() => _draft = f);
    try {
      final saved = await ref.read(formationRepositoryProvider).save(f);
      if (mounted) setState(() => _draft = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _draft = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final saved = ref.watch(formationProvider);
    final rosa = ref.watch(rosaProvider);

    if (saved.isLoading || rosa.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (saved.hasError || rosa.hasError) {
      return Center(
        child: Text('Errore nel caricamento: ${saved.error ?? rosa.error}'),
      );
    }

    final formation = _draft ?? saved.value!;
    final members = {
      for (final m in rosa.value!)
        if (m.active && m.role != ClubRole.pending) m.id: m,
    };
    final bench =
        members.values
            .where((m) => !formation.players.containsValue(m.id))
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
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
                  if (isDirettivo && formation.module != module) {
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
                        member: members[formation.players[i]],
                        onTap: isDirettivo
                            ? () async {
                                final choice = await _pickPlayer(
                                  context,
                                  slot: slot,
                                  current: members[formation.players[i]],
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
        if (isDirettivo)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Tocca un bollino per scegliere il giocatore. Le modifiche si salvano da sole.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
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
