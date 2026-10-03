import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/carta_page.dart';
import '../carta/fut_card.dart';
import 'member.dart';
import 'rosa_repository.dart';

class RosaPage extends ConsumerStatefulWidget {
  const RosaPage({super.key});

  @override
  ConsumerState<RosaPage> createState() => _RosaPageState();
}

class _RosaPageState extends ConsumerState<RosaPage> {
  /// Squadra mostrata (null = tutte).
  Team? _team;

  /// Vista a carte FUT invece dell'elenco.
  bool _cards = false;

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final rosa = ref.watch(rosaProvider);

    return rosa.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Errore nel caricamento della rosa.\n$e')),
      data: (all) {
        final active = all.where((m) => m.active).toList();
        final pending = active
            .where((m) => m.role == ClubRole.pending)
            .toList();
        final members = active.where((m) => m.role != ClubRole.pending);
        final shown = members.where((m) => m.inTeam(_team));
        final direttivo = shown
            .where((m) => m.role == ClubRole.direttivo)
            .toList();
        final giocatori = shown
            .where((m) => m.role == ClubRole.giocatore)
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _Summary(
              total: direttivo.length + giocatori.length,
              direttivo: direttivo.length,
            ),
            const SizedBox(height: 8),
            TeamFilter(
              value: _team,
              onChanged: (t) => setState(() => _team = t),
              counts: {
                null: members.length,
                for (final t in Team.values)
                  t: members.where((m) => m.teams.contains(t)).length,
              },
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.view_list_rounded),
                  label: Text('Elenco'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.style_rounded),
                  label: Text('Carte'),
                ),
              ],
              selected: {_cards},
              onSelectionChanged: (s) => setState(() => _cards = s.first),
            ),
            if (isDirettivo && pending.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 12),
                color: MilanacColors.surfaceHigh,
                child: ListTile(
                  leading: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: MilanacColors.gold,
                  ),
                  title: Text(
                    pending.length == 1
                        ? '1 richiesta di accesso'
                        : '${pending.length} richieste di accesso',
                  ),
                  subtitle: const Text('Approvale nella Sala Direttivo'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/direttivo'),
                ),
              ),
            if (_cards) ...[
              const SizedBox(height: 12),
              _CardGrid(
                members: [...direttivo, ...giocatori]
                  ..sort((a, b) => (b.overall ?? 0).compareTo(a.overall ?? 0)),
              ),
            ] else ...[
              const _Header('Direttivo', icon: Icons.star_rounded),
              for (final m in direttivo) _MemberTile(member: m),
              const _Header('Giocatori', icon: Icons.sports_soccer_rounded),
              if (giocatori.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nessun giocatore in rosa.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              for (final m in giocatori) _MemberTile(member: m),
            ],
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.direttivo});
  final int total;
  final int direttivo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: _Stat(value: '$total', label: 'Tesserati'),
            ),
            Expanded(
              child: _Stat(value: '$direttivo', label: 'Direttivo'),
            ),
            Expanded(
              child: _Stat(value: '${total - direttivo}', label: 'Giocatori'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: MilanacColors.gold,
        ),
      ),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white60),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header(this.title, {required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: MilanacColors.red),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
}

void _openCard(BuildContext context, Member m) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(builder: (_) => PlayerCardPage(memberId: m.id)));

/// Griglia di carte FUT (due per riga), ordinate per overall.
class _CardGrid extends ConsumerWidget {
  const _CardGrid({required this.members});
  final List<Member> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: 300 / 428,
    children: [
      for (final m in members)
        GestureDetector(
          onTap: () => _openCard(context, m),
          child: Consumer(
            builder: (context, ref, _) {
              final stats = ref.watch(cardStatsProvider(m.id));
              return stats == null
                  ? const SizedBox()
                  : FutCard(member: m, stats: stats);
            },
          ),
        ),
    ],
  );
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = DateFormat('d MMM yyyy', 'it').format(member.joinedAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: MemberAvatar(member: member),
        title: Text(
          member.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (member.gamertag != null) member.gamertag!,
                'Dal $joined',
              ].join(' · '),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final t in Team.values)
                  if (member.teams.contains(t)) TeamBadge(t, small: true),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RoleChip(
              member.roleLabel,
              highlight: member.role == ClubRole.direttivo,
            ),
            if (member.fieldPosition != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  member.fieldPosition!,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        onTap: () => _openCard(context, member),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip(this.label, {required this.highlight});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: highlight ? MilanacColors.gold : Colors.white12,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: highlight ? Colors.black : Colors.white,
      ),
    ),
  );
}
