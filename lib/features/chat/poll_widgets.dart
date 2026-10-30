import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/haptics.dart';
import '../../core/theme.dart';
import '../../shared/gold_loader.dart';
import '../../shared/member_photo.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'chat_repository.dart';
import 'poll.dart';

/// Il sondaggio scritto nel foglio "Nuovo sondaggio".
typedef PollDraft = ({String question, List<String> options, bool multiple});

/// Il foglio per creare un sondaggio: domanda, da 2 a 10 risposte, una o più scelte.
Future<PollDraft?> showPollComposer(BuildContext context) =>
    showModalBottomSheet<PollDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _PollComposer(),
    );

class _PollComposer extends StatefulWidget {
  const _PollComposer();

  @override
  State<_PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<_PollComposer> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  String? _problem;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _add() {
    if (_options.length >= ChatPoll.maxOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _remove(int i) {
    if (_options.length <= ChatPoll.minOptions) return;
    final removed = _options.removeAt(i);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _create() {
    final options = [for (final c in _options) c.text];
    final problem = ChatPoll.problemWith(_question.text, options);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop<PollDraft>((
      question: _question.text.trim(),
      options: [
        for (final o in options)
          if (o.trim().isNotEmpty) o.trim(),
      ],
      multiple: _multiple,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.poll_rounded, color: p.accentText, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'NUOVO SONDAGGIO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: sportFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 22,
                        letterSpacing: .5,
                        color: p.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('sondaggio-domanda'),
                controller: _question,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                maxLength: ChatPoll.maxQuestionLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Domanda',
                  hintText: "Es. Quando giochiamo l'amichevole?",
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              for (final (i, c) in _options.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey('sondaggio-risposta-$i'),
                          controller: c,
                          maxLength: ChatPoll.maxOptionLength,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Risposta ${i + 1}',
                            counterText: '',
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_options.length > ChatPoll.minOptions)
                        IconButton(
                          tooltip: 'Togli la risposta ${i + 1}',
                          onPressed: () => _remove(i),
                          icon: Icon(Icons.close_rounded, color: p.textMuted),
                        ),
                    ],
                  ),
                ),
              if (_options.length < ChatPoll.maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Aggiungi una risposta'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _multiple,
                onChanged: (v) => setState(() => _multiple = v),
                title: const Text('Più risposte'),
                subtitle: const Text('Ognuno può sceglierne più di una.'),
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _problem!,
                    style: TextStyle(color: p.danger, fontSize: 14),
                  ),
                ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Crea il sondaggio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il sondaggio dentro la bolla. Si vota toccando una risposta (con più risposte, ogni
/// tocco la aggiunge o la toglie); i risultati compaiono dopo aver votato o a sondaggio
/// chiuso, con le barre e le percentuali. "N voti" apre chi ha votato.
class PollCard extends ConsumerStatefulWidget {
  const PollCard({
    super.key,
    required this.message,
    required this.poll,
    required this.width,
  });

  final ChatMessage message;
  final ChatPoll poll;
  final double width;

  @override
  ConsumerState<PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<PollCard> {
  /// Il voto appena salvato da qui: vale finché il tempo reale non lo riporta (o se
  /// il tempo reale è giù).
  Set<int>? _saved;

  /// La risposta toccata, mentre il voto parte.
  int? _sending;

  ChatPoll get _poll => widget.poll;

  Future<void> _vote(Set<int> options, int touched) async {
    if (_sending != null) return;
    final repo = ref.read(chatRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = touched);
    Haptics.light();
    try {
      await repo.votePoll(widget.message.id, options);
      if (mounted) setState(() => _saved = Set.of(options));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Voto non salvato'))),
      );
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  void _tap(int option, PollTally tally) {
    final mine = tally.mine;
    if (!_poll.multiple) {
      if (mine.length == 1 && mine.contains(option)) return;
      _vote({option}, option);
      return;
    }
    final next = Set.of(mine);
    if (!next.remove(option)) next.add(option);
    _vote(next, option);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final local = widget.message.isLocal;
    final me = ref.watch(currentUserIdProvider);
    final provider = pollVotesProvider(widget.message.id);
    if (!local) {
      // Quando il tempo reale riporta il voto salvato da qui, vale di nuovo il suo.
      ref.listen(provider, (_, next) {
        final saved = _saved;
        final votes = next.value;
        if (saved == null || votes == null) return;
        final mine =
            votes.where((v) => v.userId == me).firstOrNull?.options ?? {};
        if (mine.length == saved.length && mine.containsAll(saved)) {
          setState(() => _saved = null);
        }
      });
    }
    final votes = local
        ? const <PollVote>[]
        : ref.watch(provider).value ?? const <PollVote>[];
    final saved = _saved;
    final tally = PollTally(_poll, [
      for (final v in votes)
        if (saved == null || v.userId != me) v,
      if (saved != null && me != null)
        PollVote(messageId: widget.message.id, userId: me, options: saved),
    ], me: me);
    final closed = _poll.closed;
    final results = tally.voted || closed;
    final leaders = closed ? tally.leaders : const <int>{};
    final canVote = !local && !closed && me != null;
    final label = [
      closed ? 'SONDAGGIO CHIUSO' : 'SONDAGGIO',
      if (_poll.multiple) 'PIÙ RISPOSTE',
    ].join(' · ');
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                closed ? Icons.lock_rounded : Icons.poll_rounded,
                size: 16,
                color: p.accentText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _poll.question,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.text,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          for (final (i, option) in _poll.options.indexed)
            _OptionRow(
              key: ValueKey('sondaggio-${widget.message.id}-$i'),
              text: option,
              chosen: tally.mine.contains(i),
              multiple: _poll.multiple,
              share: results ? tally.share(i) : null,
              count: tally.count(i),
              leader: leaders.contains(i),
              sending: _sending == i,
              onTap: canVote && _sending == null ? () => _tap(i, tally) : null,
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                    foregroundColor: p.textSecondary,
                  ),
                  onPressed: results && tally.total > 0
                      ? () => showPollVoters(context, _poll, tally)
                      : null,
                  child: Text(
                    tally.totalLabel,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const Spacer(),
              if (canVote && tally.voted)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                    foregroundColor: p.textSecondary,
                  ),
                  onPressed: _sending == null ? () => _vote({}, -1) : null,
                  child: const Text(
                    'Ritira il voto',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una risposta del sondaggio: il cerchio (o il quadrato con più risposte), il testo
/// e, con i risultati, la barra e la percentuale.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.text,
    required this.chosen,
    required this.multiple,
    required this.share,
    required this.count,
    required this.leader,
    required this.sending,
    required this.onTap,
  });

  final String text;
  final bool chosen;
  final bool multiple;

  /// La parte dei voti (da 0 a 1); null finché i risultati non si vedono.
  final double? share;
  final int count;

  /// La più votata, a sondaggio chiuso.
  final bool leader;
  final bool sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final share = this.share;
    final percent = share == null ? null : (share * 100).round();
    final icon = multiple
        ? (chosen ? Icons.check_box_rounded : Icons.check_box_outline_blank)
        : (chosen
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded);
    final barColor = leader || chosen
        ? MilanacColors.gold.withValues(alpha: .28)
        : p.text.withValues(alpha: .08);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        container: true,
        button: onTap != null,
        selected: chosen,
        onTap: onTap,
        label: [
          text,
          if (percent != null)
            '$percent per cento, ${count == 1 ? '1 voto' : '$count voti'}',
        ].join(', '),
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: chosen || leader ? p.chipBorder : p.border,
                ),
              ),
              child: Stack(
                children: [
                  if (share != null)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: share),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => FractionallySizedBox(
                            widthFactor: v.clamp(0, 1),
                            heightFactor: 1,
                            child: ColoredBox(color: barColor),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 9, 10, 9),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: sending
                              ? const GoldLoader(size: 18)
                              : Icon(
                                  icon,
                                  size: 20,
                                  color: chosen ? p.accentText : p.textMuted,
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 15,
                              color: p.text,
                              fontWeight: leader
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (percent != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$percent%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: chosen || leader
                                  ? p.accentText
                                  : p.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chi ha votato, risposta per risposta.
Future<void> showPollVoters(
  BuildContext context,
  ChatPoll poll,
  PollTally tally,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => Consumer(
    builder: (context, ref, _) {
      final p = context.pal;
      final me = ref.watch(currentUserIdProvider);
      final members = {
        for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
          m.id: m,
      };
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                'CHI HA VOTATO',
                style: TextStyle(
                  fontFamily: sportFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  letterSpacing: .5,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                poll.question,
                style: TextStyle(color: p.textSecondary, fontSize: 15),
              ),
              for (final (i, option) in poll.options.indexed)
                if (tally.count(i) > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${option.toUpperCase()} · ${tally.count(i)}',
                    style: TextStyle(
                      color: p.accentText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final id in tally.voters[i])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          members[id] == null
                              ? CircleAvatar(
                                  radius: 16,
                                  backgroundColor: p.surfaceHigher,
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 18,
                                    color: p.textMuted,
                                  ),
                                )
                              : MemberAvatar(
                                  member: members[id]!,
                                  radius: 16,
                                  showNumber: false,
                                ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              id == me
                                  ? 'Tu'
                                  : members[id]?.displayName ?? 'Ex membro',
                              style: TextStyle(color: p.text, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
            ],
          ),
        ),
      );
    },
  ),
);
