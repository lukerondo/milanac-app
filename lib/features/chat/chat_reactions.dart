import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../rosa/member.dart';
import 'chat_repository.dart';

/// Le reazioni che si possono dare (le stesse del database).
const reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '⚽'];

/// La reazione di una persona a un messaggio (una per persona).
class MessageReaction {
  const MessageReaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.at,
  });

  final String messageId;
  final String userId;
  final String emoji;
  final DateTime at;

  /// null per le reazioni tolte (emoji vuota) o le righe malformate.
  static MessageReaction? tryFromMap(Map<String, dynamic> m) {
    final emoji = m['emoji'];
    final at = DateTime.tryParse('${m['updated_at']}');
    if (emoji is! String || !reactionEmojis.contains(emoji) || at == null) {
      return null;
    }
    return MessageReaction(
      messageId: m['message_id'] as String,
      userId: m['user_id'] as String,
      emoji: emoji,
      at: at.toLocal(),
    );
  }
}

/// Le reazioni del canale per messaggio, in tempo reale.
final reactionsProvider = StreamProvider.autoDispose
    .family<Map<String, List<MessageReaction>>, String>(
      (ref, channelId) => ref
          .watch(chatRepositoryProvider)
          .watchReactions(channelId)
          .map((all) {
            final byMessage = <String, List<MessageReaction>>{};
            for (final r in all) {
              (byMessage[r.messageId] ??= []).add(r);
            }
            return byMessage;
          }),
    );

/// Le emoji di un messaggio con quante volte sono state date, dalla più data (a pari
/// merito la prima arrivata).
List<(String, int)> reactionCounts(List<MessageReaction> reactions) {
  final counts = <String, int>{};
  final first = <String, DateTime>{};
  for (final r in reactions) {
    counts.update(r.emoji, (n) => n + 1, ifAbsent: () => 1);
    final seen = first[r.emoji];
    if (seen == null || r.at.isBefore(seen)) first[r.emoji] = r.at;
  }
  return counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) {
    final byCount = b.$2.compareTo(a.$2);
    return byCount != 0 ? byCount : first[a.$1]!.compareTo(first[b.$1]!);
  });
}

/// Sotto la bolla: una pillola per emoji con il numero; la propria è dorata. Un tocco
/// mette o toglie quella reazione, la pressione lunga dice chi ha reagito.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.reactions,
    required this.me,
    required this.onToggle,
    required this.onShowWho,
    this.alignEnd = false,
  });
  final List<MessageReaction> reactions;
  final String? me;
  final ValueChanged<String> onToggle;
  final VoidCallback onShowWho;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mine = reactions.where((r) => r.userId == me).firstOrNull?.emoji;
    return Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final (emoji, count) in reactionCounts(reactions))
          Semantics(
            button: true,
            selected: emoji == mine,
            label:
                '$emoji, $count ${count == 1 ? 'reazione' : 'reazioni'}'
                '${emoji == mine ? ', anche la tua' : ''}',
            excludeSemantics: true,
            child: Material(
              color: emoji == mine ? p.accentTint : p.surfaceHigh,
              shape: StadiumBorder(
                side: BorderSide(
                  color: emoji == mine ? p.accentTintBorder : p.border,
                ),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onToggle(emoji);
                },
                onLongPress: onShowWho,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 15)),
                      if (count > 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: emoji == mine
                                ? p.accentText
                                : p.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// La riga delle emoji in cima al menu del messaggio: quella già data è cerchiata.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({
    super.key,
    required this.current,
    required this.onPick,
  });
  final String? current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in reactionEmojis)
            Semantics(
              button: true,
              selected: emoji == current,
              label: emoji == current
                  ? 'Togli la reazione $emoji'
                  : 'Reagisci con $emoji',
              excludeSemantics: true,
              child: InkResponse(
                radius: 26,
                onTap: () => onPick(emoji),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: emoji == current ? p.accentTint : null,
                    border: Border.all(
                      color: emoji == current
                          ? p.accentTintBorder
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chi ha reagito, con quale emoji (dalla più recente).
Future<void> showReactionsSheet(
  BuildContext context, {
  required List<MessageReaction> reactions,
  required Map<String, Member> members,
  required String? me,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (c) {
    final p = c.pal;
    final list = [...reactions]..sort((a, b) => b.at.compareTo(a.at));
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Reazioni',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
            ),
          ),
          for (final r in list)
            ListTile(
              leading: members[r.userId] == null
                  ? const CircleAvatar(child: Icon(Icons.person_rounded))
                  : MemberAvatar(member: members[r.userId]!, radius: 20),
              title: Text(
                r.userId == me
                    ? 'Tu'
                    : members[r.userId]?.displayName ?? 'Ex membro',
              ),
              trailing: Text(r.emoji, style: const TextStyle(fontSize: 24)),
            ),
        ],
      ),
    );
  },
);
