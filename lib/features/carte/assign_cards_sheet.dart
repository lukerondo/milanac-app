import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../risultati/match.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'carte_speciali_page.dart';
import 'special_cards_repository.dart';

/// Il Direttivo assegna le carte nero/oro di una partita: un giocatore per reparto
/// con il bonus (+1…+5). Chi ha già la blu elettrico per quella partita la tiene.
Future<void> showAssignCardsSheet(BuildContext context, ClubMatch match) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AssignSheet(match: match),
    );

/// Il reparto in cui [playerId] è già premiato, escluso [reparto] (null = nessuno).
String? repartoTakenBy(
  Map<String, String?> chosen,
  String playerId,
  String reparto,
) {
  for (final r in reparti) {
    if (r != reparto && chosen[r] == playerId) return r;
  }
  return null;
}

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.match});
  final ClubMatch match;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  final _chosen = <String, String?>{};
  final _bonus = <String, int>{for (final r in reparti) r: 5};
  bool _loaded = false;
  bool _saving = false;

  /// Le scelte già fatte si leggono una volta, solo con le carte arrivate davvero:
  /// partire da un elenco vuoto e salvare cancellerebbe le carte assegnate.
  void _loadExisting(List<SpecialCard> cards) {
    if (_loaded) return;
    _loaded = true;
    for (final c in cards) {
      if (c.matchId == widget.match.id && c.kind == CardSpecial.neroOro) {
        _chosen[c.reparto] = c.playerId;
        _bonus[c.reparto] = c.bonus;
      }
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final awards = [
      for (final r in reparti)
        if (_chosen[r] case final id?)
          CardAward(playerId: id, reparto: r, bonus: _bonus[r] ?? 5),
    ];
    // Un giocatore, una carta (lo rifiuta anche il server).
    if (awards.map((a) => a.playerId).toSet().length != awards.length) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Un giocatore riceve una sola carta nero/oro: scegli giocatori diversi.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final n = await ref
          .read(specialCardsRepositoryProvider)
          .assign(widget.match, awards);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            awards.isEmpty
                ? 'Nessuna carta nero/oro per questa partita.'
                : n == 0
                ? 'Carte aggiornate: ${awards.length} premiati.'
                : 'Carte assegnate: $n nuove. Annuncio in Comunicazioni.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Assegnazione non riuscita')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardsValue = ref.watch(specialCardsProvider);
    final rosaValue = ref.watch(rosaProvider);
    if (!cardsValue.hasValue || !rosaValue.hasValue) {
      final failed = !cardsValue.hasValue ? cardsValue : rosaValue;
      return SizedBox(
        height: 220,
        child: failed.hasError && (!failed.isLoading || failed.retrying)
            ? ErrorRetry(
                message: friendlyError(
                  failed.error!,
                  action: 'Caricamento non riuscito',
                ),
                onRetry: () => ref
                  ..invalidate(specialCardsProvider)
                  ..invalidate(rosaProvider),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final cards = cardsValue.requireValue;
    _loadExisting(cards);
    final team = widget.match.team;
    final members =
        rosaValue.requireValue
            .where(
              (m) => m.active && m.role != ClubRole.pending && m.inTeam(team),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final blue = cards
        .where((c) => c.matchId == widget.match.id && c.isBlue)
        .toList();
    final blueIds = blue.map((c) => c.playerId).toSet();
    final byId = {for (final m in members) m.id: m};
    final p = context.pal;

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
              'Carte speciali della partita',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              matchTitle(widget.match),
              style: TextStyle(fontSize: 15, color: p.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Un premiato per reparto (una sola carta a testa), con il bonus '
              'sull\'overall. La carta vale 7 giorni.',
              style: TextStyle(fontSize: 14, color: p.textMuted),
            ),
            if (blue.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final c in blue)
                SpecialCardRow(card: c, member: byId[c.playerId]),
              Text(
                'La blu elettrico è automatica e batte la nero/oro.',
                style: TextStyle(fontSize: 13, color: p.textMuted),
              ),
            ],
            for (final r in reparti) ...[
              const SizedBox(height: 12),
              _RepartoPicker(
                reparto: r,
                members: members.where((m) => !blueIds.contains(m.id)).toList(),
                value: _chosen[r],
                takenBy: (id) => repartoTakenBy(_chosen, id, r),
                bonus: _bonus[r] ?? 5,
                onChanged: (id) => setState(() => _chosen[r] = id),
                onBonus: (b) => setState(() => _bonus[r] = b),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.military_tech_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Assegna le carte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scelta del premiato di un reparto (prima chi gioca in quel reparto) e del bonus.
/// Chi è già premiato in un altro reparto compare ma non si può scegliere.
class _RepartoPicker extends StatelessWidget {
  const _RepartoPicker({
    required this.reparto,
    required this.members,
    required this.value,
    required this.takenBy,
    required this.bonus,
    required this.onChanged,
    required this.onBonus,
  });
  final String reparto;
  final List<Member> members;
  final String? value;
  final String? Function(String playerId) takenBy;
  final int bonus;
  final ValueChanged<String?> onChanged;
  final ValueChanged<int> onBonus;

  /// [other]: il reparto in cui il giocatore ha già la carta (null = libero).
  static DropdownMenuItem<String?> _item(
    Member m,
    String? other,
    Color disabled,
  ) => DropdownMenuItem(
    value: m.id,
    enabled: other == null,
    child: Text(
      '${m.displayName}${m.fieldPosition == null ? '' : ' (${m.fieldPosition})'}'
      '${other == null ? '' : ' · ha già la carta $other'}',
      overflow: TextOverflow.ellipsis,
      style: other == null ? null : TextStyle(color: disabled),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sorted = List.of(members)
      ..sort((a, b) {
        final ra = repartoOf(a.fieldPosition) == reparto ? 0 : 1;
        final rb = repartoOf(b.fieldPosition) == reparto ? 0 : 1;
        return ra != rb ? ra - rb : a.displayName.compareTo(b.displayName);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: sorted.any((m) => m.id == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '$reparto · ${repartoLabels[reparto]}',
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Nessuno')),
            for (final m in sorted)
              _item(m, takenBy(m.id), context.pal.textDisabled),
          ],
          onChanged: onChanged,
        ),
        if (value != null)
          Row(
            children: [
              Text(
                '+$bonus',
                style: TextStyle(
                  fontFamily: sportFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.pal.accentText,
                ),
              ),
              Expanded(
                child: Slider(
                  value: bonus.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '+$bonus',
                  onChanged: (v) => onBonus(v.round()),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
