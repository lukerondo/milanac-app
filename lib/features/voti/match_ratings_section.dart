import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/carta_page.dart';
import '../carta/fut_card.dart';
import '../risultati/match.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'ratings_repository.dart';

/// Nella pagina della partita: pulsante per votare, Uomo partita e classifica dei voti.
class MatchRatingsSection extends ConsumerWidget {
  const MatchRatingsSection({super.key, required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final played = match.outcome != MatchOutcome.daGiocare;
    final me = ref.watch(profileProvider).value;
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final mine = ref.watch(myRatingsProvider(match.id)).value ?? const {};
    final summary = ref.watch(ratingSummaryProvider(match.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            'VOTI E UOMO PARTITA',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ),
        if (!played)
          const Text(
            'Si vota a partita finita, quando il Direttivo inserisce il risultato.',
            style: TextStyle(color: Colors.white54),
          )
        else ...[
          if (me != null && me.isApproved)
            FilledButton.icon(
              onPressed: () => showVoteSheet(context, match),
              icon: const Icon(Icons.how_to_vote_rounded),
              label: Text(
                mine.isEmpty
                    ? 'Vota i compagni'
                    : 'Modifica i tuoi voti (${mine.length})',
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              'I voti sono segreti: si vedono solo le medie. Uomo partita con almeno 2 voti.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          ...switch (summary) {
            AsyncData(:final value) when value.isEmpty => [
              const Text(
                'Ancora nessun voto.',
                style: TextStyle(color: Colors.white54),
              ),
            ],
            AsyncData(:final value) => [
              if (value.first.isMvp && members[value.first.playerId] != null)
                _MvpCard(
                  member: members[value.first.playerId]!,
                  summary: value.first,
                ),
              for (final (i, s) in value.indexed)
                if (members[s.playerId] case final m?)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: MemberAvatar(member: m, radius: 18),
                    title: Text(m.displayName),
                    subtitle: Text(s.votes == 1 ? '1 voto' : '${s.votes} voti'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (s.isMvp)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.emoji_events_rounded,
                              color: MilanacColors.gold,
                            ),
                          ),
                        Text(
                          s.average.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: i == 0 ? MilanacColors.gold : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
            AsyncError(:final error) => [Text('Errore: $error')],
            _ => [const LinearProgressIndicator()],
          },
        ],
      ],
    );
  }
}

class _MvpCard extends ConsumerWidget {
  const _MvpCard({required this.member, required this.summary});
  final Member member;
  final RatingSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(cardStatsProvider(member.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: stats == null
                ? const SizedBox()
                : FutCard(
                    member: member,
                    stats: stats,
                    special: CardSpecial.motm,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UOMO PARTITA',
                  style: TextStyle(
                    color: MilanacColors.gold,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  member.displayName,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Media ${summary.average.toStringAsFixed(1)} · ${summary.votes} voti',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modulo dei voti: un cursore da 1 a 10 per ogni compagno (0 = non votato).
Future<void> showVoteSheet(BuildContext context, ClubMatch match) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VoteSheet(match: match),
    );

class _VoteSheet extends ConsumerStatefulWidget {
  const _VoteSheet({required this.match});
  final ClubMatch match;

  @override
  ConsumerState<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends ConsumerState<_VoteSheet> {
  Map<String, int>? _votes;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final votes = {
      for (final e in _votes!.entries)
        if (e.value > 0) e.key: e.value,
    };
    try {
      await ref
          .read(ratingsRepositoryProvider)
          .saveRatings(widget.match.id, votes);
      refreshRatings(ref, widget.match.id);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            votes.isEmpty
                ? 'Voti tolti.'
                : 'Voti salvati (${votes.length}). Grazie!',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Voti non salvati: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final mine = ref.watch(myRatingsProvider(widget.match.id));
    _votes ??= mine.value == null ? null : Map.of(mine.value!);
    final teammates =
        (ref.watch(rosaProvider).value ?? const <Member>[])
            .where(
              (m) =>
                  m.active &&
                  m.role != ClubRole.pending &&
                  m.id != me?.id &&
                  m.teams.contains(widget.match.team),
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final votes = _votes;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vota i compagni',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${widget.match.team.label} vs ${widget.match.opponent} · '
                  'lascia a "–" chi non ha giocato.',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          Expanded(
            child: votes == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final m in teammates)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              MemberAvatar(member: m, radius: 16),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 96,
                                child: Text(
                                  m.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: (votes[m.id] ?? 0).toDouble(),
                                  max: 10,
                                  divisions: 10,
                                  label: votes[m.id] == null
                                      ? '–'
                                      : '${votes[m.id]}',
                                  onChanged: (v) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      if (v < 1) {
                                        votes.remove(m.id);
                                      } else {
                                        votes[m.id] = v.round();
                                      }
                                    });
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                child: Text(
                                  votes[m.id]?.toString() ?? '–',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: MilanacColors.gold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || votes == null ? null : _save,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Salva i voti'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
