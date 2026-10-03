import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/push/push_service.dart';
import '../../core/theme.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'chat_repository.dart';

/// Conversazione di un canale (aperta anche dalle notifiche: `/chat/<slug>`).
class ChannelPage extends ConsumerStatefulWidget {
  const ChannelPage({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends ConsumerState<ChannelPage> {
  final _text = TextEditingController();
  Uint8List? _image;
  bool _sending = false;
  DateTime? _readUpTo;

  @override
  void initState() {
    super.initState();
    // Niente avviso in app per i messaggi del canale che si sta leggendo.
    PushService.instance.shouldShowInApp = (data) =>
        data['channel'] != widget.slug;
  }

  @override
  void dispose() {
    PushService.instance.shouldShowInApp = null;
    _text.dispose();
    super.dispose();
  }

  void _markRead(Channel c, List<ChatMessage> messages) {
    final newest = messages.firstOrNull?.createdAt;
    if (newest == null || (_readUpTo != null && !newest.isAfter(_readUpTo!))) {
      return;
    }
    _readUpTo = newest;
    ref.read(chatRepositoryProvider).markRead(c.id);
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _image = bytes);
  }

  Future<void> _send(Channel c) async {
    final body = _text.text.trim();
    if (body.isEmpty && _image == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(c.id, body: body.isEmpty ? null : body, image: _image);
      _text.clear();
      setState(() => _image = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Messaggio non inviato: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleMute(Channel c, bool muted) async {
    await ref.read(chatRepositoryProvider).setMuted(c.id, !muted);
    ref.invalidate(mutedChannelsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            muted
                ? 'Notifiche di ${c.name} riattivate.'
                : 'Canale silenziato: niente notifiche da ${c.name}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = ref
        .watch(channelsProvider)
        .value
        ?.where((c) => c.slug == widget.slug)
        .firstOrNull;
    final muted =
        channel != null &&
        (ref.watch(mutedChannelsProvider).value?.contains(channel.id) ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chat'),
        ),
        title: Text(channel?.name.toUpperCase() ?? 'CHAT'),
        actions: [
          if (channel != null)
            IconButton(
              tooltip: muted ? 'Riattiva notifiche' : 'Silenzia canale',
              icon: Icon(
                muted
                    ? Icons.notifications_off_rounded
                    : Icons.notifications_active_rounded,
                color: muted ? Colors.white54 : MilanacColors.gold,
              ),
              onPressed: () => _toggleMute(channel, muted),
            ),
        ],
      ),
      body: channel == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _messages(channel)),
                _composer(channel),
              ],
            ),
    );
  }

  Widget _messages(Channel c) {
    final me = ref.watch(profileProvider).value;
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final messages = ref.watch(messagesProvider(c.id));
    return messages.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (list) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _markRead(c, list);
        });
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                c.description ?? 'Scrivi il primo messaggio!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        // Lista al contrario: il più recente in basso.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            final older = i + 1 < list.length ? list[i + 1] : null;
            final newDay =
                older == null || !_sameDay(older.createdAt, m.createdAt);
            final sameAuthor =
                !newDay &&
                older.authorId == m.authorId &&
                !older.isSystem &&
                m.createdAt.difference(older.createdAt).inMinutes < 5;
            return Column(
              children: [
                if (newDay) _DaySeparator(m.createdAt),
                m.isSystem
                    ? _SystemMessage(message: m)
                    : _Bubble(
                        message: m,
                        author: members[m.authorId],
                        mine: m.authorId == me?.id,
                        showAuthor: !sameAuthor,
                        canDelete:
                            m.authorId == me?.id || (me?.isDirettivo ?? false),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _composer(Channel c) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: MilanacColors.surface,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_image != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_image!, height: 90),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Togli la foto',
                      onPressed: () => setState(() => _image = null),
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Foto',
                onPressed: _sending ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Scrivi un messaggio',
                    counterText: '',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(c),
                ),
              ),
              IconButton.filled(
                tooltip: 'Invia',
                onPressed: _sending ? null : () => _send(c),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final label = d == today
        ? 'Oggi'
        : d == today.subtract(const Duration(days: 1))
        ? 'Ieri'
        : DateFormat('EEEE d MMMM', 'it').format(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Messaggio automatico (ritardo, assenza...): al centro, con l'icona dello stato.
class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (message.meta['status']) {
      'ritardo' => (Icons.schedule_rounded, MilanacColors.gold),
      'assente' => (Icons.cancel_rounded, Colors.redAccent),
      'presente' => (Icons.check_circle_rounded, const Color(0xFF2E9E5B)),
      _ => (Icons.info_rounded, Colors.white54),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(child: Text(message.body ?? '')),
            const SizedBox(width: 8),
            Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.message,
    required this.author,
    required this.mine,
    required this.showAuthor,
    required this.canDelete,
  });
  final ChatMessage message;
  final Member? author;
  final bool mine;
  final bool showAuthor;
  final bool canDelete;

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.body != null && message.body!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copia testo'),
                onTap: () => Navigator.pop(c, 'copy'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('Elimina messaggio'),
                onTap: () => Navigator.pop(c, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body!));
    } else if (action == 'delete') {
      await ref.read(chatRepositoryProvider).delete(message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = author?.displayName ?? 'Ex membro';
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .75,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: mine ? MilanacColors.redDark : MilanacColors.surfaceHigh,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAuthor && !mine)
            Text(
              name,
              style: const TextStyle(
                color: MilanacColors.gold,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          if (message.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: _ChatImage(message: message),
            ),
          if (message.body != null && message.body!.isNotEmpty)
            Text(message.body!, style: const TextStyle(fontSize: 15)),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 8 : 2),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 34,
              child: showAuthor
                  ? CircleAvatar(
                      radius: 14,
                      backgroundColor: MilanacColors.red,
                      backgroundImage: author?.avatarUrl == null
                          ? null
                          : NetworkImage(author!.avatarUrl!),
                      child: author?.avatarUrl == null
                          ? Text(
                              name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    )
                  : null,
            ),
          GestureDetector(
            onLongPress: () => _actions(context, ref),
            child: bubble,
          ),
        ],
      ),
    );
  }
}

class _ChatImage extends ConsumerWidget {
  const _ChatImage({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget image;
    if (message.localImage != null) {
      image = Image.memory(message.localImage!, fit: BoxFit.cover);
    } else {
      final url = ref.watch(chatImageUrlProvider(message.imagePath!)).value;
      image = url == null || url.isEmpty
          ? const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          : Image.network(url, fit: BoxFit.cover);
    }
    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black),
            body: Center(child: InteractiveViewer(maxScale: 5, child: image)),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: image,
        ),
      ),
    );
  }
}
