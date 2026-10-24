import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../rosa/member.dart';
import 'chat_repository.dart';

/// Fin dove hanno letto il canale gli altri (id del profilo → ora del server
/// dell'ultimo messaggio letto), in tempo reale: le spunte dei propri messaggi.
final channelReadsProvider = StreamProvider.autoDispose
    .family<Map<String, DateTime>, String>(
      (ref, channelId) =>
          ref.watch(chatRepositoryProvider).watchReads(channelId),
    );

/// Chi vede il canale, con la stessa regola del database: membri attivi; il Direttivo
/// ovunque; nei canali di squadra chi ci gioca; nella Sala Direttivo solo il Direttivo.
List<Member> channelAudience(Channel c, Iterable<Member> members) {
  final team = Team.parse(c.team);
  return [
    for (final m in members)
      if (m.active &&
          m.role != ClubRole.pending &&
          (!c.direttivoOnly || m.role == ClubRole.direttivo) &&
          (team == null ||
              m.role == ClubRole.direttivo ||
              m.teams.contains(team)))
        m,
  ];
}

/// Chi ha letto [message] (l'autore escluso).
Set<String> readersOf(ChatMessage message, Map<String, DateTime> reads) => {
  for (final MapEntry(:key, :value) in reads.entries)
    if (key != message.authorId && !value.isBefore(message.createdAt)) key,
};

/// "Info" del proprio messaggio: chi l'ha letto e chi non ancora.
Future<void> showMessageInfo(
  BuildContext context, {
  required ChatMessage message,
  required Set<String> readers,
  required List<Member> audience,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) {
    final p = c.pal;
    final byId = {for (final m in audience) m.id: m};
    String nameOf(Member m) => m.displayName;
    final read = [
      for (final id in readers)
        if (byId[id] != null) byId[id]!,
    ]..sort((a, b) => nameOf(a).compareTo(nameOf(b)));
    final notYet = [
      for (final m in audience)
        if (m.id != message.authorId && !readers.contains(m.id)) m,
    ]..sort((a, b) => nameOf(a).compareTo(nameOf(b)));

    Widget section(
      String title,
      IconData icon,
      Color color,
      List<Member> list,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title (${list.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Nessuno',
              style: TextStyle(fontSize: 14, color: p.textMuted),
            ),
          ),
        for (final m in list)
          ListTile(
            dense: true,
            leading: MemberAvatar(member: m, radius: 18, showNumber: false),
            title: Text(nameOf(m), style: const TextStyle(fontSize: 15)),
          ),
      ],
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Info messaggio',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
            ),
          ),
          section('Letto da', Icons.done_all_rounded, p.accentText, read),
          section(
            'Non ancora letto da',
            Icons.done_rounded,
            p.textMuted,
            notYet,
          ),
        ],
      ),
    );
  },
);
