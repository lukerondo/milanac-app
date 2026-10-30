import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/notify_prefs.dart';
import '../../core/auth/providers.dart';
import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/italian_time.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../calendario/club_event.dart';
import '../calendario/events_repository.dart';
import '../carta/card_colors.dart';
import '../formazione/formation_repository.dart';
import '../formazione/formazione_page.dart' show formationPath;
import '../presenze/evening.dart';
import '../risultati/result_ui.dart' show ClubCrest, initialsOf;
import '../rosa/member.dart';

/// Nel giorno della partita la card della serata diventa il Match Day: il tabellone con
/// il conto alla rovescia, chi è pronto, la formazione e il codice del party.

/// Quanto dura una partita per il Match Day: dopo, "fischio finale".
const matchLength = Duration(minutes: 150);

/// Lo stemma contro l'avversario e il conto alla rovescia al calcio d'inizio (ore, minuti,
/// secondi); poi "in corso" e il fischio finale.
class MatchDayHeader extends ConsumerStatefulWidget {
  const MatchDayHeader({super.key, required this.event, required this.team});
  final ClubEvent event;
  final Team team;

  @override
  ConsumerState<MatchDayHeader> createState() => _MatchDayHeaderState();
}

class _MatchDayHeaderState extends ConsumerState<MatchDayHeader> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Un secondo alla volta, come il tabellone.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Gli orari degli eventi sono in ora italiana.
    final now = italianClock(ref.watch(clockProvider)());
    final kickoff = widget.event.startsAt;
    final left = kickoff.difference(now);
    final headline = matchHeadline(widget.event, widget.team);
    final opponent = headline.opponent ?? widget.event.title;
    final time = DateFormat('HH:mm').format(kickoff);
    final teamStyle = TextStyle(
      fontFamily: sportFont,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.15,
      color: p.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const ClubCrest(size: 40),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.team.label.toUpperCase(),
                maxLines: 2,
                style: teamStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'VS',
                style: TextStyle(
                  fontFamily: sportFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.accentText,
                ),
              ),
            ),
            Expanded(
              child: Text(
                opponent.toUpperCase(),
                maxLines: 2,
                textAlign: TextAlign.end,
                style: teamStyle,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: CardColors.portrait,
              ),
              child: Text(
                initialsOf(opponent),
                style: const TextStyle(
                  fontFamily: sportFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: MilanacColors.ivoryMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (left > Duration.zero)
          _Countdown(left: left, kickoff: time)
        else if (-left < matchLength)
          _Live(since: time, blink: now.second.isEven)
        else
          Text(
            'Fischio finale: il risultato lo inserisce il Direttivo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 15),
          ),
        if (headline.detail != null) ...[
          const SizedBox(height: 8),
          Text(
            headline.detail!,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textMuted, fontSize: 14),
          ),
        ],
      ],
    );
  }
}

/// Ore, minuti e secondi nelle caselle del tabellone (sempre scure, come in TV).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.kickoff});
  final Duration left;
  final String kickoff;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    String two(int n) => n.toString().padLeft(2, '0');
    final parts = [
      two(left.inHours),
      two(left.inMinutes % 60),
      two(left.inSeconds % 60),
    ];
    Widget box(String text) => Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MilanacColors.surfaceHigh, MilanacColors.black],
        ),
        border: Border.all(color: MilanacColors.gold.withValues(alpha: .6)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: sportFont,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: MilanacColors.ivory,
        ),
      ),
    );
    final colon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        ':',
        style: TextStyle(
          fontFamily: sportFont,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: p.accentText,
        ),
      ),
    );
    return Semantics(
      label:
          'Calcio d\'inizio alle $kickoff, tra ${left.inHours} ore e '
          '${left.inMinutes % 60} minuti',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              box(parts[0]),
              colon,
              box(parts[1]),
              colon,
              box(parts[2]),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'al calcio d\'inizio · $kickoff',
            style: TextStyle(color: p.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// La partita in corso: il pallino rosso che lampeggia, come la scritta LIVE in TV.
class _Live extends StatelessWidget {
  const _Live({required this.since, required this.blink});
  final String since;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Su uno schermo stretto "dalle 21:30" va a capo invece di sbordare.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AnimatedOpacity(
          opacity: blink ? 1 : .25,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.danger),
          ),
        ),
        Text(
          'IN CORSO',
          style: TextStyle(
            fontFamily: sportFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: p.text,
          ),
        ),
        Text(
          ' · dalle $since',
          style: TextStyle(color: p.textSecondary, fontSize: 15),
        ),
      ],
    );
  }
}

/// Sotto le risposte: chi è pronto (presenti e in ritardo), la formazione e il codice del
/// party, da copiare (il Direttivo lo scrive e lo cambia).
class MatchDayExtras extends ConsumerWidget {
  const MatchDayExtras({
    super.key,
    required this.event,
    required this.team,
    required this.ready,
  });
  final ClubEvent event;
  final Team team;
  final List<Member> ready;

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    Haptics.tap();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Codice del party copiato.')),
      );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _PartyCodeDialog(initial: event.partyCode),
    );
    if (code == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(eventsRepositoryProvider).setPartyCode(event.id, code);
      Haptics.confirm();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final today = italianDay(ref.watch(clockProvider)());
    final formation = ref.watch(formationProvider(team)).value;
    final published = formation != null && formation.isPublishedOn(today);
    final code = event.partyCode;
    Widget row({
      required IconData icon,
      required String text,
      String? semantics,
      VoidCallback? onTap,
      List<Widget> actions = const [],
    }) => InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(icon, size: 22, color: p.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                semanticsLabel: semantics,
                style: TextStyle(fontSize: 15, color: p.text),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: p.border, height: 1),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              'PRONTI',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: p.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ready.isEmpty
                  ? Text(
                      'Ancora nessuno: rispondi tu per primo.',
                      style: TextStyle(color: p.textSecondary, fontSize: 14),
                    )
                  : _Faces(members: ready),
            ),
          ],
        ),
        const SizedBox(height: 4),
        row(
          icon: Icons.groups_rounded,
          text: published
              ? 'Formazione ${formation.publishedModule ?? formation.module} '
                    'pubblicata'
              : 'La formazione non è ancora pubblicata',
          onTap: () => context.go(formationPath(team)),
          actions: [Icon(Icons.chevron_right_rounded, color: p.textSecondary)],
        ),
        row(
          icon: Icons.sports_esports_rounded,
          text: code != null
              ? 'Party: $code'
              : isDirettivo
              ? 'Scrivi il codice del party'
              : 'Il codice del party arriva dal Direttivo',
          onTap: code != null
              ? () => _copy(context, code)
              : isDirettivo
              ? () => _edit(context, ref)
              : null,
          actions: [
            if (code != null)
              IconButton(
                tooltip: 'Copia il codice',
                onPressed: () => _copy(context, code),
                icon: Icon(Icons.copy_rounded, color: p.accentText),
              ),
            if (isDirettivo)
              IconButton(
                tooltip: code == null ? 'Scrivi il codice' : 'Cambia il codice',
                onPressed: () => _edit(context, ref),
                icon: Icon(Icons.edit_rounded, color: p.textSecondary),
              ),
          ],
        ),
        _Reminders(event: event),
      ],
    );
  }
}

/// I promemoria della partita: quando arrivano (un'ora prima e dieci minuti prima) o che
/// sono spenti (porta alle impostazioni); per il Direttivo, nelle ore della partita,
/// "Chiama" la squadra in lobby.
class _Reminders extends ConsumerStatefulWidget {
  const _Reminders({required this.event});
  final ClubEvent event;

  @override
  ConsumerState<_Reminders> createState() => _RemindersState();
}

class _RemindersState extends ConsumerState<_Reminders> {
  late final Timer _tick;
  bool _calling = false;

  @override
  void initState() {
    super.initState();
    // Il testo cambia con l'ora (prima i due promemoria, poi solo la lobby).
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _call() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Chiamare la squadra in lobby?'),
        content: const Text(
          'Arriva una notifica a chi gioca (non agli assenti), anche a chi ha '
          'spento i promemoria.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Chiama'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(eventsRepositoryProvider);
    setState(() => _calling = true);
    try {
      await repo.callToLobby(widget.event.id);
      Haptics.confirm();
      messenger.showSnackBar(
        const SnackBar(content: Text('Squadra chiamata in lobby.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Chiamata non partita')),
        ),
      );
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final profile = ref.watch(profileProvider).value;
    final on = profile?.notifyPrefs.isOn(NotifyCategory.partite) ?? true;
    final now = italianClock(ref.watch(clockProvider)());
    final start = widget.event.startsAt;
    final hour = start.subtract(const Duration(hours: 1));
    final lobby = start.subtract(const Duration(minutes: 10));
    final canCall =
        (profile?.isDirettivo ?? false) &&
        !now.isBefore(start.subtract(lobbyCallWindow)) &&
        !now.isAfter(start.add(lobbyCallWindow));
    final hm = DateFormat('HH:mm');
    final started = !now.isBefore(start);
    final String? text = started
        ? (canCall ? 'Manca qualcuno? Chiamalo in lobby' : null)
        : !on
        ? 'Promemoria partita spenti'
        : now.isBefore(hour)
        ? 'Promemoria alle ${hm.format(hour)} e alle ${hm.format(lobby)}'
        : now.isBefore(lobby)
        ? 'Promemoria per la lobby alle ${hm.format(lobby)}'
        : 'Lobby aperta: si entra!';
    if (text == null) return const SizedBox.shrink();
    final off = !on && !started;
    return InkWell(
      onTap: off ? () => context.push('/impostazioni?sezione=notifiche') : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(
              off
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded,
              size: 22,
              color: off ? p.textMuted : p.accentText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 15, color: p.text)),
            ),
            if (off) Icon(Icons.chevron_right_rounded, color: p.textSecondary),
            if (canCall)
              TextButton.icon(
                onPressed: _calling ? null : _call,
                icon: const Icon(Icons.campaign_rounded),
                label: const Text('Chiama'),
              ),
          ],
        ),
      ),
    );
  }
}

/// I volti di chi è pronto, uno sopra l'altro (al massimo sette, poi "+3").
class _Faces extends StatelessWidget {
  const _Faces({required this.members});
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const max = 7, size = 30.0, step = 21.0;
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    return Semantics(
      label:
          '${members.length} pronti: '
          '${members.map((m) => m.displayName).join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: size,
        child: Stack(
          children: [
            for (final (i, m) in shown.indexed)
              Positioned(
                left: i * step,
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surface,
                  ),
                  child: MemberAvatar(
                    member: m,
                    radius: size / 2 - 1.5,
                    showNumber: false,
                  ),
                ),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * step + 4,
                top: 6,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontFamily: sportFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Il Direttivo scrive (o toglie) il codice del party.
class _PartyCodeDialog extends StatefulWidget {
  const _PartyCodeDialog({this.initial});
  final String? initial;

  @override
  State<_PartyCodeDialog> createState() => _PartyCodeDialogState();
}

class _PartyCodeDialogState extends State<_PartyCodeDialog> {
  late final _code = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Codice del party'),
    content: TextField(
      controller: _code,
      autofocus: true,
      maxLength: 40,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Codice',
        hintText: 'es. MILANAC21',
        helperText: 'Lo vedono tutti nella Home, da copiare.',
      ),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      if (widget.initial != null)
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Togli'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _code.text),
        child: const Text('Salva'),
      ),
    ],
  );
}
