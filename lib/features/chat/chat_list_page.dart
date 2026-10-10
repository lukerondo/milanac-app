import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../voce/voice_repository.dart';
import 'chat_repository.dart';

/// Elenco dei canali con messaggi non letti e ultimo messaggio.
class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final overview = ref.watch(chatOverviewProvider).value ?? const {};
    final muted = ref.watch(mutedChannelsProvider).value ?? const {};

    return channels.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (list) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, i) {
          final c = list[i];
          final o = overview[c.id] ?? const ChannelOverview();
          final isMuted = muted.contains(c.id);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: MilanacColors.red.withValues(alpha: .18),
              child: Icon(c.iconData, color: MilanacColors.red),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (c.direttivoOnly)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: MilanacColors.gold,
                    ),
                  ),
                if (ref.watch(channelVoiceRoomProvider(c.id)) != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.headset_mic_rounded,
                      size: 16,
                      color: MilanacColors.gold,
                    ),
                  ),
                if (isMuted)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.notifications_off_rounded,
                      size: 16,
                      color: Colors.white38,
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              o.lastAt == null ? (c.description ?? '') : o.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (o.lastAt != null)
                  Text(
                    _when(o.lastAt!),
                    style: TextStyle(
                      fontSize: 12,
                      color: o.unread > 0 ? MilanacColors.gold : Colors.white38,
                    ),
                  ),
                if (o.unread > 0) ...[
                  const SizedBox(height: 4),
                  UnreadBadge(o.unread),
                ],
              ],
            ),
            onTap: () => context.push('/chat/${c.slug}'),
          );
        },
      ),
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('HH:mm').format(t);
    }
    return DateFormat('d MMM', 'it').format(t);
  }
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: MilanacColors.red,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      count > 98 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
