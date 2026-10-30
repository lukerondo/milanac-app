import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../carta/card_colors.dart';
import '../carta/carta_page.dart';
import '../carta/mini_card.dart';
import '../carte/special_cards_repository.dart';
import '../risultati/result_ui.dart';
import 'member.dart';
import 'rosa_repository.dart';

/// Come si guarda la rosa: mini carte (predefinita) o elenco.
enum RosaView { carte, elenco }

/// La vista scelta: la cambia [RosaViewButton] nella barra in alto e resta finché
/// l'app è aperta.
final rosaViewProvider = NotifierProvider<RosaViewNotifier, RosaView>(
  RosaViewNotifier.new,
);

class RosaViewNotifier extends Notifier<RosaView> {
  @override
  RosaView build() => RosaView.carte;

  void set(RosaView view) => state = view;

  void toggle() =>
      state = state == RosaView.carte ? RosaView.elenco : RosaView.carte;
}

/// "Mostra come elenco" / "Mostra come carte": l'azione della Rosa nella barra in alto.
class RosaViewButton extends ConsumerWidget {
  const RosaViewButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asCards = ref.watch(rosaViewProvider) == RosaView.carte;
    return IconButton(
      tooltip: asCards ? 'Mostra come elenco' : 'Mostra come carte',
      icon: Icon(asCards ? Icons.view_list_rounded : Icons.grid_view_rounded),
      onPressed: () => ref.read(rosaViewProvider.notifier).toggle(),
    );
  }
}

class RosaPage extends ConsumerStatefulWidget {
  const RosaPage({super.key});

  @override
  ConsumerState<RosaPage> createState() => _RosaPageState();
}

class _RosaPageState extends ConsumerState<RosaPage> {
  final _search = TextEditingController();
  String _query = '';

  /// Squadra mostrata (null = tutte) e reparto (null = tutti).
  Team? _team;
  String? _reparto;

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

  /// Ricerca per nome sulla carta, nome e cognome o gamertag; filtri per squadra e
  /// reparto.
  bool _matches(Member m) {
    if (!m.inTeam(_team)) return false;
    final reparto = _reparto;
    if (reparto != null && repartoOf(m.fieldPosition) != reparto) {
      return false;
    }
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
    final view = ref.watch(rosaViewProvider);
    final p = context.pal;

    return AsyncView(
      value: rosa,
      onRetry: () => ref.invalidate(rosaProvider),
      action: 'Caricamento della rosa non riuscito',
      data: (all) {
        final members = all
            .where((m) => m.active && m.role != ClubRole.pending)
            .toList();
        final shown = members.where(_matches).toList();
        final byOverall = List.of(shown)
          ..sort((a, b) => (b.overall ?? 0).compareTo(a.overall ?? 0));
        int count(Team? t) => members.where((m) => m.inTeam(t)).length;

        return Column(
          children: [
            // Ricerca e filtri restano in alto mentre la rosa scorre.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Nome, cognome o gamertag',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Cancella',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _search.clear,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterPill(
                        label: 'Tutte · ${count(null)}',
                        selected: _team == null,
                        onTap: () => setState(() => _team = null),
                      ),
                      for (final t in Team.values)
                        FilterPill(
                          label: '${teamPillLabel(t)} · ${count(t)}',
                          selected: _team == t,
                          onTap: () => setState(() => _team = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterPill(
                        label: 'Tutti',
                        square: true,
                        selected: _reparto == null,
                        onTap: () => setState(() => _reparto = null),
                      ),
                      for (final r in reparti)
                        Tooltip(
                          message: repartoLabels[r],
                          child: FilterPill(
                            label: r,
                            square: true,
                            selected: _reparto == r,
                            onTap: () => setState(() => _reparto = r),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (shown.isEmpty)
                    AppCard(
                      child: Text(
                        'Nessun membro corrisponde ai filtri.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: p.textMuted),
                      ),
                    )
                  else if (view == RosaView.carte) ...[
                    MiniCardGrid(
                      members: byOverall,
                      onTap: (m) => openPlayerCard(context, m.id),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tocca una carta per aprire il profilo del giocatore.',
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                  ] else
                    ..._list(shown),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Elenco classico: prima il Direttivo, poi i giocatori.
  List<Widget> _list(List<Member> shown) {
    final groups = [
      (
        'Direttivo',
        [
          for (final m in shown)
            if (m.role == ClubRole.direttivo) m,
        ],
      ),
      (
        'Giocatori',
        [
          for (final m in shown)
            if (m.role == ClubRole.giocatore) m,
        ],
      ),
    ];
    return [
      for (final (title, list) in groups)
        if (list.isNotEmpty) ...[
          SectionLabel(title),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, m) in list.indexed) ...[
                  if (i > 0) const Divider(indent: 72, endIndent: 16),
                  _MemberRow(member: m),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
    ];
  }
}

/// Riga dell'elenco: foto, nome, gamertag e data d'ingresso, squadre, ruolo e numero.
class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final joined = DateFormat('d MMM yyyy', 'it').format(member.joinedAt);
    final special = ref.watch(activeSpecialCardProvider(member.id));
    return InkWell(
      onTap: () => openPlayerCard(context, member.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            MemberAvatar(member: member),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      if (member.gamertag != null) member.gamertag!,
                      'dal $joined',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in Team.values)
                        if (member.teams.contains(t)) TeamBadge(t, small: true),
                      if (special != null)
                        Icon(
                          special.kind.icon,
                          size: 16,
                          color: CardColors.ink(p, isBlue: special.isBlue),
                          semanticLabel: special.kind.label,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (member.fieldPosition != null)
                  Text(
                    member.fieldPosition!,
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                if (member.shirtNumber != null)
                  Text(
                    '${member.shirtNumber}',
                    style: TextStyle(
                      fontFamily: sportFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: p.accentText,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
