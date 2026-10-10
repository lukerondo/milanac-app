import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/push/push_service.dart';
import '../../core/theme.dart';
import '../../shared/link_text.dart';
import '../../shared/member_photo.dart';
import '../carte/special_cards_repository.dart';
import '../lavagna/board_model.dart';
import '../lavagna/board_painter.dart';
import '../lavagna/replay_pages.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'chat_repository.dart';
import 'voice_player.dart';
import '../voce/voice_room_sheet.dart';
import 'voice_recorder.dart';

/// Conversazione di un canale, in stile Telegram (aperta anche dalle notifiche: `/chat/<slug>`).
class ChannelPage extends ConsumerStatefulWidget {
  const ChannelPage({super.key, required this.slug, this.openVoice = false});
  final String slug;

  /// Apre subito il foglio della stanza vocale (dalla notifica "stanza aperta").
  final bool openVoice;

  @override
  ConsumerState<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends ConsumerState<ChannelPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = VoiceRecorder();
  Channel? _channel;
  Uint8List? _image;
  ChatMessage? _replyTo;
  bool _sending = false;
  bool _hasText = false;
  bool _showJump = false;
  bool _voiceShown = false;
  DateTime? _readUpTo;

  /// Ultima lettura prima di aprire il canale: sopra il primo messaggio arrivato dopo
  /// va il separatore "Nuovi messaggi".
  DateTime? _readBefore;
  bool _readBeforeRequested = false;
  bool _readBeforeLoaded = false;

  // Registrazione del vocale (tieni premuto il microfono).
  Timer? _recTimer;
  int _recSeconds = 0;
  bool _recording = false;
  bool _recCancel = false;

  @override
  void initState() {
    super.initState();
    // Niente avviso in app per i messaggi del canale che si sta leggendo.
    PushService.instance.shouldShowInApp = (data) =>
        data['channel'] != widget.slug;
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 400;
      if (show != _showJump) setState(() => _showJump = show);
    });
  }

  @override
  void dispose() {
    PushService.instance.shouldShowInApp = null;
    _recTimer?.cancel();
    _recorder.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadReadBefore(Channel c) async {
    _readBeforeRequested = true;
    final t = await ref.read(chatRepositoryProvider).lastReadAt(c.id);
    if (mounted) {
      setState(() {
        _readBefore = t;
        _readBeforeLoaded = true;
      });
    }
  }

  void _markRead(Channel c, List<ChatMessage> messages) {
    if (!_readBeforeLoaded) return;
    final newest = messages.firstOrNull?.createdAt;
    if (newest == null || (_readUpTo != null && !newest.isAfter(_readUpTo!))) {
      return;
    }
    _readUpTo = newest;
    ref.read(chatRepositoryProvider).markRead(c.id);
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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

  Future<void> _send(Channel c, {Uint8List? audio, int? seconds}) async {
    final body = audio == null ? _text.text.trim() : '';
    if (body.isEmpty && _image == null && audio == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(
            c.id,
            body: body.isEmpty ? null : body,
            image: audio == null ? _image : null,
            audio: audio,
            durationS: seconds,
            replyTo: _replyTo?.id,
          );
      HapticFeedback.lightImpact();
      if (audio == null) _text.clear();
      setState(() {
        if (audio == null) _image = null;
        _replyTo = null;
      });
      _jumpToBottom();
    } catch (e) {
      _notice('Messaggio non inviato: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (_sending || _recording) return;
    final ok = await _recorder.start();
    if (!ok) {
      _notice(
        kIsWeb
            ? 'I vocali si registrano dall\'app sul telefono.'
            : 'Serve il permesso del microfono per registrare un vocale.',
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recCancel = false;
      _recSeconds = 0;
    });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSeconds++);
      if (_recSeconds >= maxVoiceSeconds) _finishRecording(send: true);
    });
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    setState(() => _recording = false);
    if (!send || _recCancel) {
      await _recorder.cancel();
      return;
    }
    final result = await _recorder.stop();
    if (result == null) {
      _notice('Tieni premuto il microfono per registrare un vocale.');
      return;
    }
    final c = _channel;
    if (c != null) await _send(c, audio: result.bytes, seconds: result.seconds);
  }

  Future<void> _toggleMute(Channel c, bool muted) async {
    await ref.read(chatRepositoryProvider).setMuted(c.id, !muted);
    ref.invalidate(mutedChannelsProvider);
    _notice(
      muted
          ? 'Notifiche di ${c.name} riattivate.'
          : 'Canale silenziato: niente notifiche da ${c.name}.',
    );
  }

  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminare il messaggio?'),
        content: const Text('Sparisce per tutti e non si può recuperare.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(chatRepositoryProvider).delete(m);
  }

  @override
  Widget build(BuildContext context) {
    final channel = ref
        .watch(channelsProvider)
        .value
        ?.where((c) => c.slug == widget.slug)
        .firstOrNull;
    _channel = channel;
    if (channel != null && !_readBeforeRequested) _loadReadBefore(channel);
    if (channel != null && widget.openVoice && !_voiceShown) {
      _voiceShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showVoiceRoom(context, channel);
      });
    }
    final muted =
        channel != null &&
        (ref.watch(mutedChannelsProvider).value?.contains(channel.id) ?? false);
    final canWrite =
        channel != null &&
        (!channel.direttivoWrites ||
            (ref.watch(profileProvider).value?.isDirettivo ?? false));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chat'),
        ),
        title: Text(channel?.name.toUpperCase() ?? 'CHAT'),
        actions: [
          if (channel != null) VoiceRoomButton(channel: channel),
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
                VoiceRoomBanner(channel: channel),
                Expanded(
                  child: Stack(
                    children: [
                      StadiumBackground(child: _messages(channel)),
                      if (_showJump)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: FloatingActionButton.small(
                            tooltip: 'Torna in fondo',
                            backgroundColor: MilanacColors.surfaceHigh,
                            foregroundColor: Colors.white,
                            onPressed: _jumpToBottom,
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (canWrite) _composer(channel) else const _ReadOnlyNote(),
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
        final byId = {for (final m in list) m.id: m};
        // Il primo messaggio nuovo: il più vecchio tra quelli (di altri) arrivati dopo
        // l'ultima lettura. I messaggi sono dal più recente al più vecchio.
        int? firstNew;
        final readBefore = _readBefore;
        if (readBefore != null) {
          for (var i = 0; i < list.length; i++) {
            if (!list[i].createdAt.isAfter(readBefore)) break;
            if (list[i].authorId != me?.id) firstNew = i;
          }
        }
        String nameOf(String? id) =>
            members[id]?.displayName ?? (id == null ? 'MILANAC' : 'Ex membro');
        // Lista al contrario: il più recente in basso.
        return ListView.builder(
          key: const ValueKey('chat-messaggi'),
          controller: _scroll,
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
                if (i == firstNew) const _NewMessagesSeparator(),
                m.isSystem
                    ? _SystemMessage(message: m)
                    : _Bubble(
                        message: m,
                        author: members[m.authorId],
                        authorName: nameOf(m.authorId),
                        mine: m.authorId == me?.id,
                        showAuthor: !sameAuthor,
                        quoted: m.replyTo == null ? null : byId[m.replyTo],
                        quotedAuthor: m.replyTo == null
                            ? null
                            : nameOf(byId[m.replyTo]?.authorId),
                        canDelete:
                            m.authorId == me?.id || (me?.isDirettivo ?? false),
                        onReply: () => setState(() => _replyTo = m),
                        onDelete: () => _confirmDelete(m),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _composer(Channel c) {
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m.displayName,
    };
    final canSend = _hasText || _image != null;
    return SafeArea(
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
            if (_replyTo != null)
              _ReplyStrip(
                message: _replyTo!,
                author: members[_replyTo!.authorId] ?? 'Ex membro',
                onClose: () => setState(() => _replyTo = null),
              ),
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
                if (!_recording)
                  IconButton(
                    tooltip: 'Foto',
                    onPressed: _sending ? null : _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                  ),
                Expanded(
                  child: _recording
                      ? _RecordingIndicator(
                          seconds: _recSeconds,
                          cancelling: _recCancel,
                        )
                      : TextField(
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
                const SizedBox(width: 4),
                if (canSend && !_recording)
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
                  )
                else
                  _MicButton(
                    recording: _recording,
                    enabled: !_sending,
                    onTap: () => _notice(
                      'Tieni premuto per registrare un vocale, rilascia per inviarlo.',
                    ),
                    onStart: _startRecording,
                    onMove: (dx) {
                      final cancel = dx < -80;
                      if (cancel != _recCancel) {
                        setState(() => _recCancel = cancel);
                      }
                    },
                    onEnd: () => _finishRecording(send: true),
                    onCancel: () => _finishRecording(send: false),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Pulsante del microfono: tieni premuto per registrare, scorri a sinistra per annullare.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.enabled,
    required this.onTap,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
  });
  final bool recording;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final void Function(double dx) onMove;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Registra un vocale',
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPressStart: enabled ? (_) => onStart() : null,
      onLongPressMoveUpdate: (d) => onMove(d.offsetFromOrigin.dx),
      onLongPressEnd: (_) => onEnd(),
      onLongPressCancel: onCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: recording ? 54 : 44,
        height: recording ? 54 : 44,
        decoration: BoxDecoration(
          color: enabled ? MilanacColors.red : Colors.white24,
          shape: BoxShape.circle,
          boxShadow: recording
              ? [
                  BoxShadow(
                    color: MilanacColors.red.withValues(alpha: .5),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.mic_rounded,
          color: Colors.white,
          size: recording ? 28 : 22,
        ),
      ),
    ),
  );
}

/// Al posto del campo di testo mentre si registra: punto rosso, durata e istruzioni.
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.seconds, required this.cancelling});
  final int seconds;
  final bool cancelling;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        const SizedBox(width: 10),
        const Icon(Icons.circle, size: 12, color: MilanacColors.red),
        const SizedBox(width: 8),
        Text(
          formatSeconds(seconds),
          style: const TextStyle(
            fontFamily: sportFont,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          cancelling ? 'Rilascia per annullare' : '◀ Scorri per annullare',
          style: TextStyle(
            color: cancelling ? MilanacColors.redText : Colors.white54,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 10),
      ],
    ),
  );
}

/// Sopra il campo di testo: il messaggio a cui si sta rispondendo.
class _ReplyStrip extends StatelessWidget {
  const _ReplyStrip({
    required this.message,
    required this.author,
    required this.onClose,
  });
  final ChatMessage message;
  final String author;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(6, 2, 6, 6),
    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
    decoration: BoxDecoration(
      color: MilanacColors.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: MilanacColors.gold, width: 3),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.reply_rounded, size: 18, color: MilanacColors.gold),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rispondi a $author',
                style: const TextStyle(
                  color: MilanacColors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Text(
                message.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Annulla risposta',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}

/// Canale in sola lettura (Comunicazioni): vi scrive solo il Direttivo.
class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) => const SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Icon(Icons.campaign_rounded, color: MilanacColors.gold, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Qui scrive solo il Direttivo: avvisi ufficiali, formazioni ed eventi.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Separatore "Nuovi messaggi" sopra il primo messaggio non ancora letto.
class _NewMessagesSeparator extends StatelessWidget {
  const _NewMessagesSeparator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const Expanded(child: Divider(color: MilanacColors.gold)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Nuovi messaggi',
            style: TextStyle(
              color: MilanacColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
        ),
        const Expanded(child: Divider(color: MilanacColors.gold)),
      ],
    ),
  );
}

/// Messaggio automatico (formazione pubblicata, carte speciali...): al centro.
class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (message.systemType) {
      'formation' => (Icons.sports_soccer_rounded, MilanacColors.gold),
      'special_cards' => (Icons.military_tech_rounded, MilanacColors.gold),
      _ => (Icons.info_rounded, Colors.white54),
    };
    final route = switch (message.systemType) {
      'formation' => '/formazione',
      'special_cards' => '/carte-speciali',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: GestureDetector(
        onTap: route == null ? null : () => context.push(route),
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
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.message,
    required this.author,
    required this.authorName,
    required this.mine,
    required this.showAuthor,
    required this.canDelete,
    required this.onReply,
    required this.onDelete,
    this.quoted,
    this.quotedAuthor,
  });
  final ChatMessage message;
  final Member? author;
  final String authorName;
  final bool mine;
  final bool showAuthor;
  final bool canDelete;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  /// Messaggio citato (se ancora tra quelli caricati).
  final ChatMessage? quoted;
  final String? quotedAuthor;

  Future<void> _actions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Rispondi'),
              onTap: () => Navigator.pop(c, 'reply'),
            ),
            if (message.hasText)
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
    switch (action) {
      case 'reply':
        onReply();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body!));
      case 'delete':
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Chi ha la carta speciale della settimana ha l'anello colorato sul volto.
    final special = author == null
        ? null
        : ref.watch(activeSpecialCardProvider(author!.id));
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .78,
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      decoration: BoxDecoration(
        color: mine ? MilanacColors.redDark : MilanacColors.surfaceHigh,
        border: message.isAnnouncement
            ? Border.all(color: MilanacColors.gold, width: 1.5)
            : null,
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
          if (message.isAnnouncement)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.campaign_rounded,
                    size: 16,
                    color: MilanacColors.gold,
                  ),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'AVVISO DEL DIRETTIVO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MilanacColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showAuthor && !mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                authorName,
                style: const TextStyle(
                  color: MilanacColors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          if (message.replyTo != null)
            _Quote(message: quoted, author: quotedAuthor, mine: mine),
          if (message.isReplay)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: _ReplayBubble(message: message),
            ),
          if (message.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: _ChatImage(message: message),
            ),
          if (message.hasAudio && !message.isReplay)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: _VoiceBubble(message: message, mine: mine),
            ),
          if (message.isExpired) const _ExpiredNote(),
          if (message.hasText)
            LinkText(
              message.body!,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              linkColor: mine ? const Color(0xFFFFD98A) : MilanacColors.gold,
            ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                DateFormat('HH:mm').format(message.createdAt),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
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
              width: 36,
              child: showAuthor
                  ? (author == null
                        ? const CircleAvatar(
                            radius: 15,
                            child: Icon(Icons.person_rounded, size: 16),
                          )
                        : Container(
                            padding: const EdgeInsets.all(2),
                            decoration: special == null
                                ? null
                                : BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: special.kind.color,
                                      width: 2,
                                    ),
                                  ),
                            child: MemberAvatar(
                              member: author!,
                              radius: special == null ? 15 : 13,
                              showNumber: false,
                            ),
                          ))
                  : null,
            ),
          Flexible(
            child: GestureDetector(
              onLongPress: () => _actions(context),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

/// Il messaggio citato dentro una bolla.
class _Quote extends StatelessWidget {
  const _Quote({
    required this.message,
    required this.author,
    required this.mine,
  });
  final ChatMessage? message;
  final String? author;
  final bool mine;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6, top: 2),
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: mine ? .25 : .3),
      borderRadius: BorderRadius.circular(8),
      border: const Border(
        left: BorderSide(color: MilanacColors.gold, width: 3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          author ?? 'Messaggio precedente',
          style: const TextStyle(
            color: MilanacColors.gold,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        Text(
          message?.summary ?? 'Messaggio non più disponibile',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    ),
  );
}

/// Replay della lavagna: il campo con il pulsante Play (si riproduce nell'app).
class _ReplayBubble extends StatelessWidget {
  const _ReplayBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final board = BoardState.fromJson(
      (message.meta['board'] as Map?)?.cast<String, dynamic>(),
    );
    final title = (message.meta['title'] as String?) ?? 'Schema';
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.draw_rounded, size: 15, color: MilanacColors.gold),
              SizedBox(width: 4),
              Text(
                'SCHEMA CON AUDIO',
                style: TextStyle(
                  color: MilanacColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            alignment: Alignment.center,
            children: [
              BoardPreview(state: board),
              if (!message.isExpired)
                IconButton.filled(
                  tooltip: 'Riproduci il replay',
                  style: IconButton.styleFrom(
                    backgroundColor: MilanacColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(14),
                  ),
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => ReplayPage(message: message),
                        ),
                      ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 32),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (message.durationS != null && !message.isExpired)
            Text(
              '${formatSeconds(message.durationS!)} · scade dopo 3 giorni',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// L'allegato (foto o vocale) è scaduto dopo 60 giorni.
class _ExpiredNote extends StatelessWidget {
  const _ExpiredNote();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 2, bottom: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_disabled_rounded, size: 16, color: Colors.white54),
        SizedBox(width: 6),
        Text(
          'Allegato scaduto',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    ),
  );
}

/// Messaggio vocale: ascolta/pausa, barra di avanzamento e durata.
class _VoiceBubble extends ConsumerWidget {
  const _VoiceBubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final path = message.audioPath;
    final messenger = ScaffoldMessenger.of(context);
    final url = path == null
        ? ''
        : await ref.read(chatRepositoryProvider).audioUrl(path);
    if (url.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vocale non disponibile nella demo.')),
      );
      return;
    }
    await ref.read(voicePlayerProvider.notifier).toggle(message.id, url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voicePlayerProvider);
    final active = state.playingId == message.id;
    final total = message.durationS ?? state.duration?.inSeconds ?? 0;
    final shown = active ? state.position.inSeconds : total;
    final color = mine ? Colors.white : MilanacColors.gold;
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          IconButton.filled(
            tooltip: active && state.playing ? 'Pausa' : 'Ascolta',
            style: IconButton.styleFrom(
              backgroundColor: color,
              foregroundColor: mine ? MilanacColors.redDark : Colors.black,
            ),
            onPressed: () => _toggle(context, ref),
            icon: Icon(
              active && state.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: active ? state.progress : 0,
                    minHeight: 5,
                    color: color,
                    backgroundColor: color.withValues(alpha: .3),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatSeconds(shown),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
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
