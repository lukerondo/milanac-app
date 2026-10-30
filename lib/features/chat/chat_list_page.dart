import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/ui.dart';
import '../voce/voice_call.dart';
import '../voce/voice_repository.dart';
import '../voce/voice_room_sheet.dart';
import 'chat_repository.dart';
import 'chat_widgets.dart';

export 'chat_search_page.dart'
    show ChatSearchButton, ChatSearchPage, showChatSearch;

/// Elenco dei canali (tavola 12): in cima le stanze vocali aperte, poi i canali con
/// l'ultimo messaggio, l'ora e i non letti. La ricerca nei messaggi è l'azione
/// [ChatSearchButton] della barra in alto.
class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final overview = ref.watch(chatOverviewProvider).value ?? const {};
    final muted = ref.watch(mutedChannelsProvider).value ?? const {};
    final call = ref.watch(voiceCallProvider);
    // Canali con la stanza vocale aperta (o quella in cui sei).
    final rooms = {
      for (final c in channels.value ?? const <Channel>[])
        if (call.isIn(c.id) ||
            ref.watch(channelVoiceRoomProvider(c.id)) != null)
          c.id,
    };

    return AsyncView<List<Channel>>(
      value: channels,
      onRetry: () => ref.invalidate(channelsProvider),
      action: 'Canali non caricati',
      data: (list) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final c in list)
            if (rooms.contains(c.id)) ...[
              VoiceRoomBanner(channel: c, padding: EdgeInsets.zero),
              const SizedBox(height: 14),
            ],
          if (list.isEmpty)
            const _NoChannels()
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, c) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 72),
                    _ChannelRow(
                      channel: c,
                      overview: overview[c.id] ?? const ChannelOverview(),
                      muted: muted.contains(c.id),
                      roomOpen: rooms.contains(c.id),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Una riga dell'elenco: icona, nome (con le cuffie se la stanza è aperta), ultimo
/// messaggio o descrizione, ora e messaggi non letti.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.overview,
    required this.muted,
    required this.roomOpen,
  });
  final Channel channel;
  final ChannelOverview overview;
  final bool muted;
  final bool roomOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final o = overview;
    final unread = o.unread > 0;
    final last = o.lastAt;
    return InkWell(
      onTap: () => context.push('/chat/${channel.slug}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            ChannelTile(channel: channel, highlighted: unread),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.text,
                          ),
                        ),
                      ),
                      if (roomOpen) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.headphones_rounded,
                          size: 16,
                          color: p.accentText,
                          semanticLabel: 'stanza vocale aperta',
                        ),
                      ],
                      if (muted) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.notifications_off_rounded,
                          size: 16,
                          color: p.textMuted,
                          semanticLabel: 'notifiche silenziate',
                        ),
                      ],
                    ],
                  ),
                  Text(
                    last == null ? channel.shortDescription : o.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textMuted),
                  ),
                ],
              ),
            ),
            if (last != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    chatWhen(last),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      color: unread ? p.accentText : p.textMuted,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(height: 4),
                    Semantics(
                      label: o.unread == 1
                          ? '1 non letto'
                          : '${o.unread} non letti',
                      excludeSemantics: true,
                      child: CountBadge(o.unread),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoChannels extends StatelessWidget {
  const _NoChannels();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
    child: Text(
      'Nessun canale per ora.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, color: context.pal.textMuted),
    ),
  );
}
