import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart' show ContentWidth;
import '../../shared/async_view.dart';
import '../../shared/club_links.dart';
import '../../shared/club_links_editor.dart';
import '../../shared/member_photo.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import '../calendario/club_event.dart';
import '../calendario/event_editor.dart';
import '../calendario/events_repository.dart';
import '../chat/chat_repository.dart';
import '../formazione/formation_repository.dart';
import '../formazione/formazione_page.dart';
import '../presenze/attendance.dart';
import '../presenze/attendance_repository.dart';
import '../presenze/attendance_ui.dart';
import '../presenze/evening.dart';
import '../presenze/presenze_page.dart'
    show answerAttendance, describeAttendance;
import '../risultati/match_editor.dart';
import '../rosa/member.dart';
import '../rosa/member_editor.dart';
import '../rosa/rosa_repository.dart';
import '../regolamento/rules_repository.dart';
import '../voce/voice_repository.dart';

/// Sala Direttivo: la stanza riservata dove si gestisce il club. In alto le cose da
/// fare oggi, poi i minuti voce del mese e la gestione.
/// Visibile solo al Direttivo (menu filtrato e redirect nel router).
class DirettivoPage extends ConsumerWidget {
  const DirettivoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(rosaProvider).value;
    final members = (all ?? const <Member>[])
        .where((m) => m.active && m.role != ClubRole.pending)
        .toList();
    // Stasera in Italia, come sul server.
    final today = italianDay(ref.watch(clockProvider)());
    final attendance = ref.watch(attendanceProvider).value;
    final answered = {
      for (final e in attendance ?? const [])
        if (e.date == today) e.playerId,
    };
    // Finché i dati non arrivano i numeri restano vuoti (non "tutti senza risposta").
    final missing = all == null || attendance == null
        ? null
        : members.where((m) => !answered.contains(m.id)).length;
    final formations = [
      for (final t in Team.values) ref.watch(formationProvider(t)).value,
    ];
    final toPublish = formations.contains(null)
        ? null
        : formations
              .where((f) => !f!.isPublishedOn(today) || f.hasUnpublishedChanges)
              .length;
    final proposals =
        (ref.watch(sharedLinksProvider(LinkCategory.video)).value ??
                const <SharedLink>[])
            .where((l) => !l.isPublished)
            .length;

    final voiceMinutes = ref.watch(voiceMinutesProvider).value ?? 0;
    final rules = ref.watch(latestRulesProvider);
    final noRules = rules.hasValue && rules.value == null;

    void push(Widget page) => Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => page));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (noRules) ...[
          AppCard(
            important: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            onTap: () => context.go('/regolamento/scrivi'),
            child: const _RulesReminder(),
          ),
          const SizedBox(height: 16),
        ],
        const SectionLabel('Da fare oggi'),
        const SizedBox(height: 8),
        AppCard(
          important: true,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _TodoRow(
                value: missing,
                title: 'Senza risposta stasera',
                subtitle: 'Correggi anche dopo le $attendanceDeadlineLabel',
                onTap: () => push(const TonightAttendancePage()),
              ),
              const Divider(indent: 74),
              _TodoRow(
                value: toPublish,
                title: 'Formazioni da pubblicare',
                subtitle: 'Milan AC e Futuro',
                onTap: () => push(const FormationEditorPage()),
              ),
              const Divider(indent: 74),
              _TodoRow(
                value: proposals,
                title: proposals == 1 ? 'Video proposto' : 'Video proposti',
                subtitle: 'Pubblica o scarta',
                onTap: () => context.go('/mondo'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _VoiceMinutes(minutes: voiceMinutes),
        const SizedBox(height: 24),
        const SectionLabel('Gestione'),
        const SizedBox(height: 8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ManageRow(
                icon: Icons.edit_calendar_rounded,
                title: 'Nuovo evento',
                onTap: () => showEventEditor(context),
              ),
              const Divider(indent: 52),
              _ManageRow(
                icon: Icons.campaign_rounded,
                title: 'Avviso a tutti',
                onTap: () => _sendAnnouncement(context, ref),
              ),
              const Divider(indent: 52),
              _ManageRow(
                icon: Icons.scoreboard_rounded,
                title: 'Nuovo risultato',
                onTap: () => showMatchEditor(context),
              ),
              const Divider(indent: 52),
              _ManageRow(
                icon: Icons.groups_rounded,
                title: 'Rosa e squadre',
                onTap: () => push(const RosaManagementPage()),
              ),
              const Divider(indent: 52),
              _ManageRow(
                icon: Icons.menu_book_rounded,
                title: 'Regolamento e storia',
                onTap: () => context.push('/regolamento'),
              ),
              const Divider(indent: 52),
              _ManageRow(
                icon: Icons.link_rounded,
                title: 'Contatti social',
                onTap: () => push(
                  ClubLinksEditorPage(
                    initial: ref.read(clubLinksProvider).value ?? const [],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Avviso ufficiale: va in Comunicazioni, dove scrive solo il Direttivo,
  /// e arriva a tutti come notifica.
  Future<void> _sendAnnouncement(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _AnnouncementDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final channels =
          ref.read(channelsProvider).value ??
          await ref.read(chatRepositoryProvider).watchChannels().first;
      final target =
          channels.where((c) => c.slug == 'comunicazioni').firstOrNull ??
          channels.firstWhere((c) => c.slug == 'main');
      await ref
          .read(chatRepositoryProvider)
          .send(
            target.id,
            body: text.trim(),
            meta: const {'type': 'announcement'},
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Avviso inviato in ${target.name} a tutto il club.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Avviso non inviato'))),
      );
    }
  }
}

/// Promemoria del regolamento d'ingresso ancora da scrivere.
class _RulesReminder extends StatelessWidget {
  const _RulesReminder();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        const IconTile(Icons.menu_book_rounded),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Regolamento d\'ingresso da scrivere',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Nessuna versione pubblicata: i nuovi membri entrano senza '
                'accettarlo. Scrivilo e pubblicalo.',
                style: TextStyle(fontSize: 14, color: p.textMuted),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: p.textMuted),
      ],
    );
  }
}

/// Una cosa da fare oggi: il numero in oro (grigio se non c'è niente da fare),
/// cosa e dove.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  /// null = dati non ancora arrivati.
  final int? value;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '${value ?? '–'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: sportFont,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: (value ?? 0) > 0 ? p.accentText : p.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minuti della stanza vocale usati nel mese, con la barra su 10.000.
/// Toccando si va alla chat, dove sta la stanza vocale.
class _VoiceMinutes extends StatelessWidget {
  const _VoiceMinutes({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final number = NumberFormat.decimalPattern('it');
    final share = (minutes / voiceMinutesPerMonth).clamp(0.0, 1.0);
    // Oro pieno nel tema scuro, oro scuro (leggibile) nel chiaro; oltre l'80% del
    // mese la barra avvisa.
    final bar = share >= .8
        ? p.warning
        : p.isDark
        ? p.accent
        : p.accentText;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      onTap: () => context.go('/chat'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Minuti voce del mese',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ),
              Text(
                number.format(minutes),
                style: TextStyle(
                  fontFamily: sportFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: p.accentText,
                ),
              ),
              Text(
                ' su ${number.format(voiceMinutesPerMonth)}',
                style: TextStyle(fontSize: 15, color: p.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: p.divider),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share,
                    child: ColoredBox(color: bar),
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

/// Una voce della gestione: icona oro e nome.
class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: p.accentText),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16, color: p.text),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
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

/// Barra in alto delle pagine a schermo intero della Sala Direttivo: indietro,
/// titolo e il filo d'oro.
AppBar _fullScreenBar(String title) => AppBar(
  title: Text(title),
  flexibleSpace: const Align(alignment: Alignment.topCenter, child: GoldRule()),
);

/// Le squadre di un giocatore ("Milan AC · Futuro").
String _teamsLabel(Set<Team> teams) => [
  for (final t in Team.values)
    if (teams.contains(t)) teamTabLabel(t),
].join(' · ');

/// Rosa e squadre: il Direttivo sposta i giocatori tra Milan AC e Futuro e modifica i dati.
class RosaManagementPage extends ConsumerStatefulWidget {
  const RosaManagementPage({super.key});

  @override
  ConsumerState<RosaManagementPage> createState() => _RosaManagementPageState();
}

class _RosaManagementPageState extends ConsumerState<RosaManagementPage> {
  Team? _team;

  Future<void> _setTeams(Member m, Set<Team> teams) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(rosaRepositoryProvider).save(m.copyWith(teams: teams));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Modifica non riuscita')),
        ),
      );
    }
  }

  /// Un membro rimosso torna nella rosa (e può di nuovo entrare nell'app).
  Future<void> _reactivate(Member m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(rosaRepositoryProvider).save(m.copyWith(active: true));
      messenger.showSnackBar(
        SnackBar(content: Text('${m.displayName} è di nuovo nella rosa.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Modifica non riuscita')),
        ),
      );
    }
  }

  /// Eliminazione definitiva dell'account (doppia conferma).
  Future<void> _deleteAccount(Member m) async {
    if (!await confirmDeleteAccount(context, m) || !mounted) return;
    await deleteMemberAccount(context, ref, m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _fullScreenBar('ROSA E SQUADRE'),
      body: ContentWidth(
        child: AsyncView(
          value: ref.watch(rosaProvider),
          onRetry: () => ref.invalidate(rosaProvider),
          data: _page,
        ),
      ),
    );
  }

  Widget _page(List<Member> all) {
    final p = context.pal;
    final members =
        all.where((m) => m.active && m.role != ClubRole.pending).toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final removed = all.where((m) => !m.active).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    // Registrati ma non ancora entrati nel club (li vede solo il Direttivo).
    final pending =
        all.where((m) => m.active && m.role == ClubRole.pending).toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final shown = members.where((m) => m.inTeam(_team)).toList();
    return Column(
      children: [
        // I filtri restano in alto, nella fascia sotto la barra.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterPill(
                label: 'Tutte · ${members.length}',
                selected: _team == null,
                onTap: () => setState(() => _team = null),
              ),
              for (final t in Team.values)
                FilterPill(
                  label:
                      '${teamTabLabel(t)} · '
                      '${members.where((m) => m.teams.contains(t)).length}',
                  selected: _team == t,
                  onTap: () => setState(() => _team = t),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Tocca le squadre per spostare un giocatore (anche in entrambe). '
                'Tocca il nome per ruolo, numero e altri dati.',
                style: TextStyle(fontSize: 14, color: p.textMuted),
              ),
              const SizedBox(height: 12),
              for (final m in shown) ...[
                _MemberCard(
                  member: m,
                  onEdit: () => showMemberEditor(context, m),
                  onTeams: (t) => _setTeams(m, t),
                ),
                const SizedBox(height: 8),
              ],
              if (removed.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionLabel('Rimossi'),
                const SizedBox(height: 4),
                Text(
                  'Non possono entrare nell\'app finché non vengono riattivati. '
                  'Tocca un nome per eliminarne definitivamente l\'account.',
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
                const SizedBox(height: 8),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (final (i, m) in removed.indexed) ...[
                        if (i > 0) const Divider(),
                        AttendanceMemberRow(
                          member: m,
                          detail: m.fullName == m.displayName
                              ? m.roleLabel
                              : m.fullName,
                          // Toccando il nome si elimina definitivamente l'account.
                          onTap: () => _deleteAccount(m),
                          trailing: OutlinedButton(
                            onPressed: () => _reactivate(m),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            child: const Text('Riattiva'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionLabel('In attesa di entrare'),
                const SizedBox(height: 4),
                Text(
                  'Si sono registrati ma non sono ancora entrati nel club. Se non '
                  'li conosci, elimina il loro account.',
                  style: TextStyle(fontSize: 14, color: p.textMuted),
                ),
                const SizedBox(height: 8),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (final (i, m) in pending.indexed) ...[
                        if (i > 0) const Divider(),
                        AttendanceMemberRow(
                          member: m,
                          detail: !m.registrationCompleted
                              ? 'Registrazione non completata'
                              : m.fullName != m.displayName
                              ? '${m.fullName} · deve accettare il regolamento'
                              : 'Deve accettare il regolamento',
                          trailing: IconButton(
                            tooltip: 'Elimina l\'account di ${m.displayName}',
                            icon: Icon(
                              Icons.delete_forever_rounded,
                              color: p.danger,
                            ),
                            onPressed: () => _deleteAccount(m),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Un giocatore in Rosa e squadre: dati (tocca per modificarli) e le sue squadre.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onTeams,
  });
  final Member member;
  final VoidCallback onEdit;
  final ValueChanged<Set<Team>> onTeams;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = member;
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AttendanceMemberRow(
            member: m,
            detail: [
              m.roleLabel,
              if (m.fieldPosition != null) m.fieldPosition!,
              if (m.shirtNumber != null) '#${m.shirtNumber}',
            ].join(' · '),
            trailing: Icon(Icons.edit_rounded, size: 20, color: p.textMuted),
            onTap: onEdit,
          ),
          const SizedBox(height: 6),
          TeamsPicker(value: m.teams, onChanged: onTeams),
        ],
      ),
    );
  }
}

/// Presenze di stasera viste dal Direttivo: chi non ha risposto, ritardi, assenze e
/// presenti; toccando un giocatore si corregge la sua risposta, anche dopo le 18:30.
class TonightAttendancePage extends ConsumerWidget {
  const TonightAttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosa = ref.watch(rosaProvider);
    final attendance = ref.watch(attendanceProvider);
    final now = ref.watch(clockProvider)();
    // Stasera in Italia, come sul server.
    final today = italianDay(now);
    final events = ref.watch(eventsProvider).value ?? const <ClubEvent>[];

    void retry() {
      ref.invalidate(rosaProvider);
      ref.invalidate(attendanceProvider);
    }

    return Scaffold(
      appBar: _fullScreenBar('PRESENZE DI STASERA'),
      body: ContentWidth(
        child: AsyncView(
          value: rosa,
          onRetry: retry,
          data: (all) => AsyncView(
            value: attendance,
            onRetry: retry,
            data: (entries) => _list(
              context,
              ref,
              all: all,
              entries: entries,
              events: events,
              today: today,
              now: now,
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref, {
    required List<Member> all,
    required List<AttendanceEntry> entries,
    required List<ClubEvent> events,
    required DateTime today,
    required DateTime now,
  }) {
    final p = context.pal;
    final members =
        all.where((m) => m.active && m.role != ClubRole.pending).toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final tonight = {
      for (final e in entries)
        if (e.date == today) e.playerId: e,
    };
    List<Member> withStatus(AttendanceStatus? s) => members
        .where(
          (m) => s == null
              ? !tonight.containsKey(m.id)
              : tonight[m.id]?.status == s,
        )
        .toList();

    Future<void> edit(Member m) async {
      final entry = tonight[m.id];
      final status = await showModalBottomSheet<AttendanceStatus>(
        context: context,
        showDragHandle: true,
        builder: (_) => _EditSheet(member: m, entry: entry),
      );
      if (status == null || !context.mounted) return;
      await answerAttendance(
        context,
        ref,
        playerId: m.id,
        day: today,
        status: status,
        current: entry,
        event: eveningEvent(events, today, teams: {mainTeam(m.teams)}),
      );
    }

    String detail(Member m) {
      final entry = tonight[m.id];
      if (entry == null) return 'Non ha ancora risposto';
      return describeAttendance(entry) +
          (entry.setBy != null ? ' · segnata dal Direttivo' : '');
    }

    List<Widget> group(
      String title,
      AttendanceStatus? status,
      List<Member> list, {
      Color? color,
    }) => [
      const SizedBox(height: 20),
      AttendanceGroupLabel(
        title: title,
        count: list.length,
        status: status,
        color: color,
      ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        Text('Nessuno.', style: TextStyle(fontSize: 14, color: p.textMuted))
      else
        AppCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final (i, m) in list.indexed) ...[
                if (i > 0) const Divider(),
                AttendanceMemberRow(
                  member: m,
                  detail: detail(m),
                  detailColor: tonight[m.id] == null
                      ? null
                      : p.status(
                          tonight[m.id]!.status,
                          auto: tonight[m.id]!.auto,
                        ),
                  trailing: RowTrailingText(_teamsLabel(m.teams)),
                  onTap: () => edit(m),
                ),
              ],
            ],
          ),
        ),
    ];

    final closed = !answersOpen(today, now);
    final day = DateFormat('EEEE d MMMM', 'it').format(today);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          '${day[0].toUpperCase()}${day.substring(1)} · '
          '${closed ? 'risposte chiuse alle $attendanceDeadlineLabel' : 'risposte aperte fino alle $attendanceDeadlineLabel'}. '
          'Tocca un giocatore per correggere la sua risposta: resta registrato chi l\'ha fatto.',
          style: TextStyle(fontSize: 15, color: p.textSecondary),
        ),
        // Prima chi manca: è quello che il Direttivo deve sistemare.
        ...group('Senza risposta', null, withStatus(null), color: p.accentText),
        ...group(
          'In ritardo',
          AttendanceStatus.ritardo,
          withStatus(AttendanceStatus.ritardo),
        ),
        ...group(
          'Assenti',
          AttendanceStatus.assente,
          withStatus(AttendanceStatus.assente),
        ),
        ...group(
          'Presenti',
          AttendanceStatus.presente,
          withStatus(AttendanceStatus.presente),
        ),
      ],
    );
  }
}

/// Foglio per correggere la risposta di un giocatore: restituisce lo stato scelto.
class _EditSheet extends StatelessWidget {
  const _EditSheet({required this.member, required this.entry});
  final Member member;
  final AttendanceEntry? entry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MemberAvatar(member: member, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: sportFont,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .5,
                          color: p.text,
                        ),
                      ),
                      Text(
                        entry == null
                            ? 'Non ha ancora risposto per stasera.'
                            : 'Ora: ${describeAttendance(entry!)}',
                        style: TextStyle(fontSize: 15, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Segna per lui (Direttivo):',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: p.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            AttendanceButtons(
              selected: entry?.status,
              inline: true,
              onAnswer: (s) => Navigator.pop(context, s),
            ),
          ],
        ),
      ),
    );
  }
}
