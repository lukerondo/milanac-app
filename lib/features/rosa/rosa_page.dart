import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/carta_page.dart';
import '../carta/fut_card.dart';
import '../carta/mini_card.dart';
import '../carte/special_cards_repository.dart';
import 'member.dart';
import 'rosa_repository.dart';

/// Come si guarda la rosa: mini carte (predefinita), carte grandi o elenco.
enum RosaView {
  mini('Mini', Icons.grid_view_rounded),
  carte('Carte', Icons.style_rounded),
  elenco('Elenco', Icons.view_list_rounded);

  const RosaView(this.label, this.icon);
  final String label;
  final IconData icon;
}

class RosaPage extends ConsumerStatefulWidget {
  const RosaPage({super.key});

  @override
  ConsumerState<RosaPage> createState() => _RosaPageState();
}

class _RosaPageState extends ConsumerState<RosaPage> {
  final _search = TextEditingController();
  String _query = '';

  /// Squadra mostrata (null = tutte), reparto (null = tutti), solo Direttivo.
  Team? _team;
  String? _reparto;
  bool _onlyDirettivo = false;
  RosaView _view = RosaView.mini;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Ricerca per nome sulla carta, nome e cognome o gamertag; filtri per squadra,
  /// reparto e Direttivo.
  bool _matches(Member m) {
    if (!m.inTeam(_team)) return false;
    if (_reparto != null && repartoOf(m.fieldPosition) != _reparto) return false;
    if (_onlyDirettivo && m.role != ClubRole.direttivo) return false;
    if (_query.isEmpty) return true;
    final text = [
      m.displayName,
      m.fullName,
      m.gamertag ?? '',
    ].join(' ').toLowerCase();
    return text.contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final rosa = ref.watch(rosaProvider);

    return rosa.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Errore nel caricamento della rosa.\n$e')),
      data: (all) {
        final members = all
            .where((m) => m.active && m.role != ClubRole.pending)
            .toList();
        final shown = members.where(_matches).toList();
        final direttivo = shown
            .where((m) => m.role == ClubRole.direttivo)
            .toList();
        final giocatori = shown
            .where((m) => m.role == ClubRole.giocatore)
            .toList();
        final byOverall = List.of(shown)
          ..sort((a, b) => (b.overall ?? 0).compareTo(a.overall ?? 0));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _Summary(
              total: members.length,
              direttivo: members
                  .where((m) => m.role == ClubRole.direttivo)
                  .length,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cerca per nome, cognome o gamertag',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Cancella',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _search.clear,
                      ),
              ),
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
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Tutti i reparti'),
                  selected: _reparto == null,
                  onSelected: (_) => setState(() => _reparto = null),
                ),
                for (final r in reparti)
                  ChoiceChip(
                    label: Text(r),
                    tooltip: repartoLabels[r],
                    selected: _reparto == r,
                    onSelected: (_) => setState(() => _reparto = r),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.star_rounded, size: 16),
                  label: const Text('Solo Direttivo'),
                  selected: _onlyDirettivo,
                  onSelected: (v) => setState(() => _onlyDirettivo = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<RosaView>(
              segments: [
                for (final v in RosaView.values)
                  ButtonSegment(
                    value: v,
                    icon: Icon(v.icon),
                    label: Text(v.label),
                  ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nessun membro corrisponde ai filtri.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              switch (_view) {
                RosaView.mini => MiniCardGrid(
                  members: byOverall,
                  onTap: (m) => openPlayerCard(context, m.id),
                ),
                RosaView.carte => _CardGrid(members: byOverall),
                RosaView.elenco => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (direttivo.isNotEmpty)
                      const _Header('Direttivo', icon: Icons.star_rounded),
                    for (final m in direttivo) _MemberTile(member: m),
                    if (giocatori.isNotEmpty)
                      const _Header(
                        'Giocatori',
                        icon: Icons.sports_soccer_rounded,
                      ),
                    for (final m in giocatori) _MemberTile(member: m),
                  ],
                ),
              },
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
        padding: const EdgeInsets.symmetric(vertical: 14),
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
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
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
          onTap: () => openPlayerCard(context, m.id),
          child: Consumer(
            builder: (context, ref, _) {
              final stats = ref.watch(cardStatsProvider(m.id));
              final special = ref.watch(activeSpecialCardProvider(m.id));
              return stats == null
                  ? const SizedBox()
                  : FutCard(
                      member: m,
                      stats: stats,
                      special: special?.kind,
                      bonus: special?.bonus ?? 0,
                    );
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
    final special = ref.watch(activeSpecialCardProvider(member.id));
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
                if (special != null)
                  Icon(special.kind.icon, size: 14, color: special.kind.color),
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
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (member.fieldPosition != null)
                    Text(
                      member.fieldPosition!,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (member.shirtNumber != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${member.shirtNumber}',
                      style: const TextStyle(
                        fontFamily: sportFont,
                        color: MilanacColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        onTap: () => openPlayerCard(context, member.id),
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
