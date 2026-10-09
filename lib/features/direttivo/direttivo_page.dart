import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/club_links.dart';
import '../../shared/club_links_editor.dart';
import '../../shared/member_photo.dart';
import '../calendario/event_editor.dart';
import '../chat/chat_repository.dart';
import '../formazione/formation_repository.dart';
import '../formazione/formazione_page.dart';
import '../presenze/attendance.dart';
import '../presenze/attendance_repository.dart';
import '../presenze/presenze_page.dart' show describeAttendance, statusColor;
import '../risultati/match_editor.dart';
import '../rosa/member.dart';
import '../rosa/member_editor.dart';
import '../rosa/rosa_repository.dart';
import 'pending_request_tile.dart';

/// Sala Direttivo: la stanza riservata dove si gestisce il club.
/// Visibile solo al Direttivo (menu filtrato e redirect nel router).
class DirettivoPage extends ConsumerWidget {
  const DirettivoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(rosaProvider).value ?? const <Member>[];
    final pending = all
        .where((m) => m.active && m.role == ClubRole.pending)
        .toList();
    final members = all
        .where((m) => m.active && m.role != ClubRole.pending)
        .toList();
    final today = dayOnly(DateTime.now());
    final answered = {
      for (final e in ref.watch(attendanceProvider).value ?? const [])
        if (e.date == today) e.playerId,
    };
    final missing = members.where((m) => !answered.contains(m.id)).length;
    final toPublish = Team.values.where((t) {
      final f = ref.watch(formationProvider(t)).value;
      return f == null || !f.isPublishedToday || f.hasUnpublishedChanges;
    }).length;

    void push(Widget page) => Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => page));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [MilanacColors.redDark, MilanacColors.black],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: MilanacColors.gold.withValues(alpha: .5)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.admin_panel_settings_rounded,
                size: 40,
                color: MilanacColors.gold,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SALA DIRETTIVO',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: MilanacColors.gold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Riservata al Direttivo: formazioni, rosa e squadre, avvisi.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Stat(
                value: pending.length,
                label: pending.length == 1
                    ? 'richiesta di accesso'
                    : 'richieste di accesso',
                highlight: pending.isNotEmpty,
              ),
              _Stat(
                value: missing,
                label: 'senza risposta stasera',
                highlight: missing > 0,
                onTap: () => push(const TonightAttendancePage()),
              ),
              _Stat(
                value: toPublish,
                label: 'formazioni da pubblicare',
                highlight: toPublish > 0,
                onTap: () => push(const FormationEditorPage()),
              ),
            ],
          ),
        ),
        if (pending.isNotEmpty) ...[
          const _Header('Richieste di accesso'),
          for (final m in pending) PendingRequestTile(member: m),
        ],
        const _Header('Gestione'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _Action(
              icon: Icons.sports_soccer_rounded,
              title: 'Formazioni',
              subtitle: 'Schiera, sposta e pubblica',
              onTap: () => push(const FormationEditorPage()),
            ),
            _Action(
              icon: Icons.groups_rounded,
              title: 'Rosa e squadre',
              subtitle: 'Milan AC / Futuro, ruoli',
              onTap: () => push(const RosaManagementPage()),
            ),
            _Action(
              icon: Icons.how_to_reg_rounded,
              title: 'Presenze di stasera',
              subtitle: 'Chi manca all\'appello',
              onTap: () => push(const TonightAttendancePage()),
            ),
            _Action(
              icon: Icons.campaign_rounded,
              title: 'Avviso a tutti',
              subtitle: 'Notifica a tutto il club',
              onTap: () => _sendAnnouncement(context, ref),
            ),
            _Action(
              icon: Icons.lock_rounded,
              title: 'Chat del Direttivo',
              subtitle: 'Solo per voi',
              onTap: () => context.push('/chat/direttivo'),
            ),
            _Action(
              icon: Icons.event_available_rounded,
              title: 'Nuovo evento',
              subtitle: 'Partita, allenamento…',
              onTap: () => showEventEditor(context),
            ),
            _Action(
              icon: Icons.scoreboard_rounded,
              title: 'Nuovo risultato',
              subtitle: 'Punteggio e marcatori',
              onTap: () => showMatchEditor(context),
            ),
            _Action(
              icon: Icons.share_rounded,
              title: 'Contatti social',
              subtitle: 'Link nel menu',
              onTap: () => push(
                ClubLinksEditorPage(
                  initial: ref.read(clubLinksProvider).value ?? const [],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _sendAnnouncement(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _AnnouncementDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final channels = ref.read(channelsProvider).value ?? const <Channel>[];
      final main =
          channels.where((c) => c.slug == 'main').firstOrNull ??
          (await ref.read(chatRepositoryProvider).watchChannels().first)
              .firstWhere((c) => c.slug == 'main');
      await ref
          .read(chatRepositoryProvider)
          .send(
            main.id,
            body: text.trim(),
            meta: const {'type': 'announcement'},
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Avviso inviato in MILANAC Main a tutto il club.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Avviso non inviato: $e')));
    }
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog();

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Avviso a tutto il club'),
    content: TextField(
      controller: _text,
      autofocus: true,
      minLines: 2,
      maxLines: 6,
      maxLength: 500,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'es. Stasera si gioca alle 22: tutti in lobby alle 21:45',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, _text.text),
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('Invia'),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.highlight = false,
    this.onTap,
  });
  final int value;
  final String label;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: highlight ? MilanacColors.gold : Colors.white54,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: MilanacColors.red, size: 28),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Rosa e squadre: il Direttivo sposta i giocatori tra MILANAC e FUTURO e modifica i dati.
class RosaManagementPage extends ConsumerStatefulWidget {
  const RosaManagementPage({super.key});

  @override
  ConsumerState<RosaManagementPage> createState() => _RosaManagementPageState();
}

class _RosaManagementPageState extends ConsumerState<RosaManagementPage> {
  Team? _team;

  Future<void> _setTeams(Member m, Set<Team> teams) async {
    try {
      await ref.read(rosaRepositoryProvider).save(m.copyWith(teams: teams));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Modifica non riuscita: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members =
        (ref.watch(rosaProvider).value ?? const <Member>[])
            .where((m) => m.active && m.role != ClubRole.pending)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final shown = members.where((m) => m.inTeam(_team)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('ROSA E SQUADRE')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text(
            'Tocca le squadre per spostare un giocatore (anche in entrambe). '
            'Tocca il nome per ruolo, numero e altri dati.',
            style: TextStyle(color: Colors.white60),
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
          for (final m in shown)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 8),
                      leading: MemberAvatar(member: m),
                      title: Text(
                        m.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          m.roleLabel,
                          if (m.fieldPosition != null) m.fieldPosition!,
                          if (m.shirtNumber != null) '#${m.shirtNumber}',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.edit_rounded, size: 18),
                      onTap: () => showMemberEditor(context, m),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: TeamsPicker(
                        value: m.teams,
                        onChanged: (t) => _setTeams(m, t),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Presenze di stasera viste dal Direttivo: chi non ha risposto, ritardi e assenze.
class TonightAttendancePage extends ConsumerWidget {
  const TonightAttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        (ref.watch(rosaProvider).value ?? const <Member>[])
            .where((m) => m.active && m.role != ClubRole.pending)
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final today = dayOnly(DateTime.now());
    final tonight = {
      for (final e in ref.watch(attendanceProvider).value ?? const [])
        if (e.date == today) e.playerId: e,
    };
    List<Member> withStatus(AttendanceStatus? s) => members
        .where(
          (m) => s == null
              ? !tonight.containsKey(m.id)
              : tonight[m.id]?.status == s,
        )
        .toList();

    Widget group(String title, Color color, List<Member> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(
            '${title.toUpperCase()} (${list.length})',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('Nessuno.', style: TextStyle(color: Colors.white38)),
          ),
        for (final m in list)
          ListTile(
            dense: true,
            leading: MemberAvatar(member: m, radius: 16),
            title: Text(m.displayName),
            subtitle: tonight[m.id] == null
                ? Text(m.teams.map((t) => t.short).join(' · '))
                : Text(describeAttendance(tonight[m.id]!)),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('PRESENZE DI STASERA')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          group('Senza risposta', MilanacColors.gold, withStatus(null)),
          group(
            'In ritardo',
            statusColor(AttendanceStatus.ritardo),
            withStatus(AttendanceStatus.ritardo),
          ),
          group(
            'Assenti',
            statusColor(AttendanceStatus.assente),
            withStatus(AttendanceStatus.assente),
          ),
          group(
            'Presenti',
            statusColor(AttendanceStatus.presente),
            withStatus(AttendanceStatus.presente),
          ),
        ],
      ),
    );
  }
}
