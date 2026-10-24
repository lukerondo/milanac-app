import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../rosa/member.dart';
import 'chat_repository.dart';

/// Gli id menzionati in un messaggio (meta.mentions, già ripulito dal database).
List<String> mentionIdsOf(ChatMessage m) {
  final ids = m.meta['mentions'];
  return ids is List
      ? [
          for (final id in ids)
            if (id is String) id,
        ]
      : const [];
}

/// La menzione che si sta scrivendo: una "@" a inizio parola prima del cursore,
/// seguita da al massimo tre parole, senza spazio in fondo (finita, come dopo aver
/// scelto un nome). null se il cursore non è in una menzione.
({int start, String query})? mentionAt(String text, int cursor) {
  if (cursor < 1 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  // "mario@gmail.com" non è una menzione: prima della @ ci vuole uno spazio.
  if (at > 0 && before[at - 1].trim().isNotEmpty) return null;
  final query = before.substring(at + 1);
  if (query.contains('\n') ||
      query.length > 30 ||
      query.startsWith(' ') ||
      query.endsWith(' ') ||
      ' '.allMatches(query).length > 2) {
    return null;
  }
  return (start: at, query: query);
}

/// I membri che corrispondono a quello che si è scritto dopo la "@": il nome sulla
/// carta, il nome, il cognome o il gamertag che iniziano così (maiuscole uguali alle
/// minuscole). Al massimo [limit], in ordine di nome.
List<Member> mentionCandidates(
  String query,
  Iterable<Member> audience, {
  String? me,
  int limit = 5,
}) {
  final q = query.trim().toLowerCase();
  bool matches(Member m) {
    if (q.isEmpty) return true;
    final words = [
      m.displayName,
      m.firstName,
      m.lastName,
      m.gamertag,
    ].whereType<String>().map((w) => w.toLowerCase());
    return words.any(
      (w) => w.startsWith(q) || w.split(' ').any((part) => part.startsWith(q)),
    );
  }

  return (audience.where((m) => m.id != me && matches(m)).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName)))
      .take(limit)
      .toList();
}

/// Le menzioni ancora presenti nel testo da inviare: di quelle scelte ([picked]: id →
/// nome sulla carta) restano solo quelle con "@nome" ancora scritto.
List<String> mentionsIn(String text, Map<String, String> picked) => [
  for (final MapEntry(:key, :value) in picked.entries)
    if (text.contains('@$value')) key,
];

/// I suggerimenti sopra la barra di scrittura mentre si scrive una menzione.
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({
    super.key,
    required this.candidates,
    required this.onPick,
  });
  final List<Member> candidates;
  final ValueChanged<Member> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in candidates)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPick(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    MemberAvatar(member: m, radius: 16, showNumber: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                    ),
                    if (m.gamertag != null && m.gamertag!.isNotEmpty)
                      Text(
                        m.gamertag!,
                        style: TextStyle(fontSize: 13, color: p.textMuted),
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
