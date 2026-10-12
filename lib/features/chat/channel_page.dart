import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/audio_focus.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/push/push_service.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/link_text.dart';
import '../../shared/member_photo.dart';
import '../carte/special_cards_repository.dart';
import '../lavagna/board_model.dart';
import '../lavagna/board_painter.dart';
import '../lavagna/replay_pages.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'channel_messages.dart';
import 'chat_repository.dart';
import 'voice_player.dart';
import '../voce/voice_room_sheet.dart';
import 'voice_recorder.dart';

/// Conversazione di un canale, in stile Telegram (aperta anche dalle notifiche: `/chat/<slug>`).
class ChannelPage extends ConsumerWidget {
  const ChannelPage({super.key, required this.slug, this.openVoice = false});
  final String slug;

  /// Apre subito la stanza vocale (dalla notifica "stanza aperta").
  final bool openVoice;

  static void _exit(BuildContext context) =>
      context.canPop() ? context.pop() : context.go('/chat');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final channel = channels.value?.where((c) => c.slug == slug).firstOrNull;
    if (channel != null) {
      // Una conversazione per canale: aprendo un altro canale (anche con router.go,
      // che riusa la pagina) si riparte da zero.
      return _ChannelView(
        key: ValueKey(channel.id),
        channel: channel,
        openVoice: openVoice,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _exit(context)),
        title: const Text('CHAT'),
      ),
      body: AsyncView<List<Channel>>(
        value: channels,
        onRetry: () => ref.invalidate(channelsProvider),
        action: 'Canali non caricati',
        data: (_) => _ChannelUnavailable(onExit: () => _exit(context)),
      ),
    );
  }
}

class _ChannelView extends ConsumerStatefulWidget {
  const _ChannelView({
    super.key,
    required this.channel,
    required this.openVoice,
  });
  final Channel channel;
  final bool openVoice;

  @override
  ConsumerState<_ChannelView> createState() => _ChannelViewState();
}

class _ChannelViewState extends ConsumerState<_ChannelView> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  /// Quando compare la striscia "Connessione persa" la lista cambia posto tra i widget:
  /// con la chiave globale resta la stessa e non perde il punto in cui si era.
  final _listKey = GlobalKey(debugLabel: 'chat-messaggi');
  late final VoiceRecorder _recorder;
  late final AudioFocus _audioFocus;
  Uint8List? _image;
  ChatMessage? _replyTo;
  bool _hasText = false;
  bool _showJump = false;
  DateTime? _readUpTo;

  /// Ultima lettura prima di aprire il canale: sopra il primo messaggio arrivato dopo
  /// va il separatore "Nuovi messaggi".
  DateTime? _readBefore;
  bool _readBeforeLoaded = false;

  // Registrazione del vocale (tieni premuto il microfono).
  Timer? _recTimer;
  int _recSeconds = 0;

  /// Il dito è ancora sul microfono.
  bool _pressing = false;

  /// Il registratore sta partendo (cartella temporanea, encoder) o chiudendo il file.
  bool _starting = false;
  bool _stopping = false;
  bool _recording = false;
  bool _recCancel = false;

  /// Niente avviso in app per i messaggi del canale che si sta leggendo.
  bool _pushFilter(Map<String, dynamic> data) =>
      data['channel'] != widget.channel.slug;

  static const _noMicrophone = kIsWeb
      ? 'I vocali si registrano dall\'app sul telefono.'
      : 'Serve il permesso del microfono per registrare un vocale.';

  Channel get _channel => widget.channel;

  ChannelMessages get _conversation =>
      ref.read(messagesProvider(_channel.id).notifier);

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(voiceRecorderFactoryProvider)();
    _audioFocus = ref.read(audioFocusProvider.notifier);
    PushService.instance.shouldShowInApp = _pushFilter;
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 400;
      if (show != _showJump) setState(() => _showJump = show);
      _maybeLoadMore();
    });
    _loadReadBefore();
    if (widget.openVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showVoiceRoom(context, _channel);
      });
    }
  }

  @override
  void dispose() {
    // Con router.go da un canale all'altro la pagina nuova parte prima che questa si
    // chiuda: il filtro si toglie solo se è ancora il nostro.
    if (PushService.instance.shouldShowInApp == _pushFilter) {
      PushService.instance.shouldShowInApp = null;
    }
    _recTimer?.cancel();
    if (_recording) {
      // I provider non si cambiano mentre i widget si smontano: subito dopo.
      final focus = _audioFocus;
      scheduleMicrotask(() {
        try {
          focus.release(AudioUse.registrazioneVocale);
        } catch (_) {}
      });
    }
    _recorder.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadReadBefore() async {
    DateTime? readBefore;
    try {
      readBefore = await ref
          .read(chatRepositoryProvider)
          .lastReadAt(_channel.id);
    } catch (_) {
      // Senza l'ultima lettura niente separatore, ma il canale si segna letto lo stesso.
    }
    if (!mounted) return;
    setState(() {
      _readBefore = readBefore;
      _readBeforeLoaded = true;
    });
  }

  void _markRead(List<ChatMessage> messages) {
    if (!_readBeforeLoaded) return;
    // L'ora del server del messaggio più recente arrivato (quelli in invio da qui hanno
    // ancora l'ora del telefono, che può essere sbagliata).
    final newest = messages.where((m) => !m.isLocal).firstOrNull?.createdAt;
    if (newest == null || (_readUpTo != null && !newest.isAfter(_readUpTo!))) {
      return;
    }
    _readUpTo = newest;
    unawaited(_saveRead(newest));
  }

  Future<void> _saveRead(DateTime until) async {
    try {
      await ref
          .read(chatRepositoryProvider)
          .markRead(_channel.id, until: until);
    } catch (_) {
      // Si riprova con il prossimo messaggio (o alla prossima apertura).
    }
  }

  /// Vicino al messaggio più vecchio caricato (in cima): la pagina precedente.
  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients) return;
    final history = ref.read(messagesProvider(_channel.id)).value;
    if (history == null ||
        !history.hasMore ||
        history.loadingMore ||
        history.loadMoreFailed) {
      return;
    }
    if (_scroll.position.extentAfter > 800) return;
    _conversation.loadMore();
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
    if (mounted) setState(() => _image = bytes);
  }

  /// Il messaggio compare subito nella conversazione (anche se il tempo reale è giù) e
  /// la barra si libera; se non parte resta "non inviato" e si riprova toccandolo.
  Future<void> _send({Uint8List? audio, int? seconds}) async {
    if (!mounted) return;
    final body = audio == null ? _text.text.trim() : '';
    final image = audio == null ? _image : null;
    if (body.isEmpty && image == null && audio == null) return;
    final reply = _replyTo;
    final conversation = _conversation;
    if (audio == null) _text.clear();
    setState(() {
      if (audio == null) _image = null;
      _replyTo = null;
    });
    HapticFeedback.lightImpact();
    _jumpToBottom();
    _report(
      await conversation.send(
        body: body.isEmpty ? null : body,
        image: image,
        audio: audio,
        durationS: seconds,
        replyTo: reply?.id,
      ),
    );
  }

  Future<void> _retry(ChatMessage m) async =>
      _report(await _conversation.retry(m.id));

  void _report(SendReport report) {
    if (report.quoteDropped) {
      _notice(
        'Il messaggio citato è stato eliminato: inviato senza citazione.',
      );
    }
    final error = report.error;
    if (error != null) {
      _notice(friendlyError(error, action: 'Messaggio non inviato'));
    }
  }

  /// Tocco sul microfono: il permesso si chiede qui, fuori dalla pressione lunga (il
  /// dialogo del sistema la interromperebbe e il vocale partirebbe a dito alzato).
  Future<void> _micTapped() async {
    final allowed = await _recorder.hasPermission(request: true);
    _notice(
      allowed
          ? 'Tieni premuto per registrare un vocale, rilascia per inviarlo.'
          : _noMicrophone,
    );
  }

  Future<void> _startRecording() async {
    if (_recording || _starting || _stopping) return;
    _pressing = true;
    _starting = true;
    bool started;
    try {
      started = await _recorder.start(requestPermission: false);
    } catch (_) {
      started = false;
    } finally {
      _starting = false;
    }
    if (!mounted) {
      if (started) unawaited(_recorder.cancel());
      return;
    }
    if (!started) {
      _notice(
        kIsWeb
            ? _noMicrophone
            : 'Tocca il microfono per dare il permesso di registrare.',
      );
      return;
    }
    if (!_pressing) {
      // Il dito si è alzato mentre il registratore partiva: niente vocale.
      await _recorder.cancel();
      return;
    }
    _audioFocus.claim(AudioUse.registrazioneVocale);
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
    // Se il registratore sta ancora partendo ci pensa _startRecording.
    if (!_recording) return;
    _recTimer?.cancel();
    setState(() => _recording = false);
    _audioFocus.release(AudioUse.registrazioneVocale);
    final keep = send && !_recCancel;
    ({Uint8List bytes, int seconds, String path})? result;
    _stopping = true;
    try {
      if (keep) {
        result = await _recorder.stop();
      } else {
        await _recorder.cancel();
      }
    } catch (_) {
      result = null;
    } finally {
      _stopping = false;
    }
    if (!keep) return;
    if (result == null) {
      _notice('Tieni premuto il microfono per registrare un vocale.');
      return;
    }
    await _send(audio: result.bytes, seconds: result.seconds);
  }

  Future<void> _toggleMute(bool muted) async {
    final c = _channel;
    try {
      await ref.read(chatRepositoryProvider).setMuted(c.id, !muted);
    } catch (e) {
      _notice(friendlyError(e, action: 'Notifiche non cambiate'));
      return;
    }
    if (!mounted) return;
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
    if (ok != true || !mounted) return;
    try {
      // Sparisce dalla conversazione appena il server conferma.
      await ref.read(chatRepositoryProvider).delete(m);
    } catch (e) {
      _notice(friendlyError(e, action: 'Messaggio non eliminato'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = _channel;
    // Un altro audio prende il posto (un vocale da ascoltare, la stanza vocale):
    // la registrazione si annulla.
    ref.listen(audioFocusProvider, (_, uses) {
      if (_recording && !uses.contains(AudioUse.registrazioneVocale)) {
        _finishRecording(send: false);
      }
    });
    // Il messaggio a cui si sta rispondendo è stato eliminato: via la citazione.
    ref.listen(messagesProvider(channel.id), (_, next) {
      final reply = _replyTo;
      final deleted = next.value?.deleted ?? const {};
      if (reply != null && deleted.contains(reply.id)) {
        setState(() => _replyTo = null);
        _notice('Il messaggio a cui rispondevi è stato eliminato.');
      }
    });
    final muted =
        ref.watch(mutedChannelsProvider).value?.contains(channel.id) ?? false;
    final canWrite =
        !channel.direttivoWrites ||
        (ref.watch(profileProvider).value?.isDirettivo ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => ChannelPage._exit(context)),
        title: Text(channel.name.toUpperCase()),
        actions: [
          VoiceRoomButton(channel: channel),
          IconButton(
            tooltip: muted ? 'Riattiva notifiche' : 'Silenzia canale',
            icon: Icon(
              muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded,
              color: muted ? Colors.white54 : MilanacColors.gold,
            ),
            onPressed: () => _toggleMute(muted),
          ),
        ],
      ),
      body: Column(
        children: [
          VoiceRoomBanner(channel: channel),
          Expanded(
            child: Stack(
              children: [
                StadiumBackground(child: _messages()),
                if (_showJump)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      tooltip: 'Torna in fondo',
                      backgroundColor: MilanacColors.surfaceHigh,
                      foregroundColor: Colors.white,
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
              ],
            ),
          ),
          if (canWrite) _composer() else const _ReadOnlyNote(),
        ],
      ),
    );
  }

  Widget _messages() {
    final c = _channel;
    final me = ref.watch(profileProvider).value;
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final provider = messagesProvider(c.id);
    // Anche se il tempo reale cade per un momento la conversazione resta (con la
    // striscia "Connessione persa"), senza perdere il punto in cui si era.
    return AsyncView<ChannelHistory>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      action: 'Messaggi non caricati',
      data: (history) {
        final list = history.messages;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _markRead(list);
          _maybeLoadMore();
        });
        if (list.isEmpty && !history.hasMore) {
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
        // l'ultima lettura. I messaggi sono dal più recente al più vecchio. Se l'ultima
        // lettura è prima di tutti quelli caricati il separatore aspetta le pagine
        // precedenti, altrimenti finirebbe nel posto sbagliato.
        int? firstNew;
        final readBefore = _readBefore;
        if (readBefore != null &&
            (!history.hasMore ||
                (list.isNotEmpty &&
                    !list.last.createdAt.isAfter(readBefore)))) {
          for (var i = 0; i < list.length; i++) {
            if (!list[i].createdAt.isAfter(readBefore)) break;
            if (list[i].authorId != me?.id && !list[i].isLocal) firstNew = i;
          }
        }
        String nameOf(String? id) =>
            members[id]?.displayName ?? (id == null ? 'MILANAC' : 'Ex membro');
        final showTop =
            history.hasMore || history.loadingMore || history.loadMoreFailed;
        // Lista al contrario: il più recente in basso.
        return KeyedSubtree(
          key: const ValueKey('chat-messaggi'),
          child: ListView.builder(
            key: _listKey,
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            itemCount: list.length + (showTop ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == list.length) {
                return _LoadMoreRow(
                  loading: history.loadingMore,
                  failed: history.loadMoreFailed,
                  onRetry: () => ref.read(provider.notifier).loadMore(),
                );
              }
              final m = list[i];
              final older = i + 1 < list.length ? list[i + 1] : null;
              final newDay =
                  older == null || !_sameDay(older.createdAt, m.createdAt);
              final sameAuthor =
                  !newDay &&
                  older.authorId == m.authorId &&
                  !older.isSystem &&
                  m.createdAt.difference(older.createdAt).inMinutes < 5;
              final mine = m.authorId == me?.id;
              final replyTo = m.replyTo;
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
                          mine: mine,
                          showAuthor: !sameAuthor,
                          quote: replyTo == null
                              ? null
                              : _Quote(
                                  messageId: replyTo,
                                  loaded: byId[replyTo],
                                  deleted: history.deleted.contains(replyTo),
                                  nameOf: nameOf,
                                  mine: mine,
                                ),
                          canDelete:
                              !m.isLocal &&
                              (mine || (me?.isDirettivo ?? false)),
                          onReply: () => setState(() => _replyTo = m),
                          onDelete: () => _confirmDelete(m),
                          onRetry: () => _retry(m),
                          onDiscard: () =>
                              ref.read(provider.notifier).discard(m.id),
                        ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _composer() {
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
                    onPressed: _pickImage,
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
                          onSubmitted: (_) => _send(),
                        ),
                ),
                const SizedBox(width: 4),
                if (canSend && !_recording)
                  IconButton.filled(
                    tooltip: 'Invia',
                    onPressed: () => _send(),
                    icon: const Icon(Icons.send_rounded),
                  )
                else
                  _MicButton(
                    recording: _recording,
                    onTap: _micTapped,
                    onStart: _startRecording,
                    onMove: (dx) {
                      final cancel = dx < -80;
                      if (cancel != _recCancel) {
                        setState(() => _recCancel = cancel);
                      }
                    },
                    onEnd: () {
                      _pressing = false;
                      _finishRecording(send: true);
                    },
                    onCancel: () {
                      _pressing = false;
                      _finishRecording(send: false);
                    },
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

/// Il canale non c'è (eliminato, o riservato e non visibile a chi è entrato).
class _ChannelUnavailable extends StatelessWidget {
  const _ChannelUnavailable({required this.onExit});
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: 40, color: Colors.white38),
          const SizedBox(height: 12),
          const Text(
            'Canale non disponibile',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Non esiste più oppure non è tra quelli che puoi vedere.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onExit,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Torna alla chat'),
          ),
        ],
      ),
    ),
  );
}

/// In cima alla conversazione: i messaggi precedenti in arrivo, oppure "Riprova".
class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
    required this.loading,
    required this.failed,
    required this.onRetry,
  });
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Center(
      child: failed
          ? TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Messaggi precedenti non caricati · Riprova'),
            )
          : loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    ),
  );
}

/// Pulsante del microfono: tieni premuto per registrare, scorri a sinistra per annullare.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.onTap,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
  });
  final bool recording;
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
      onTap: onTap,
      onLongPressStart: (_) => onStart(),
      onLongPressMoveUpdate: (d) => onMove(d.offsetFromOrigin.dx),
      onLongPressEnd: (_) => onEnd(),
      onLongPressCancel: onCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: recording ? 54 : 44,
        height: recording ? 54 : 44,
        decoration: BoxDecoration(
          color: MilanacColors.red,
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
        const SizedBox(width: 12),
        // Su schermi stretti (o con il testo grande) le istruzioni si accorciano.
        Expanded(
          child: Text(
            cancelling ? 'Rilascia per annullare' : '◀ Scorri per annullare',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cancelling ? MilanacColors.redText : Colors.white54,
              fontSize: 13,
            ),
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
    required this.onRetry,
    required this.onDiscard,
    this.quote,
  });
  final ChatMessage message;
  final Member? author;
  final String authorName;
  final bool mine;
  final bool showAuthor;
  final bool canDelete;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  /// Messaggio non partito: si riprova o si toglie.
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// Il messaggio citato (se risponde a un altro).
  final Widget? quote;

  Future<void> _actions(BuildContext context) async {
    final failed = message.failed;
    final canReply = !message.isLocal;
    final canCopy = message.hasText;
    final canRemove = failed || canDelete;
    if (!failed && !canReply && !canCopy && !canRemove) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failed)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Riprova'),
                onTap: () => Navigator.pop(c, 'retry'),
              ),
            if (canReply)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Rispondi'),
                onTap: () => Navigator.pop(c, 'reply'),
              ),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copia testo'),
                onTap: () => Navigator.pop(c, 'copy'),
              ),
            if (canRemove)
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
      case 'retry':
        onRetry();
      case 'reply':
        onReply();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body!));
      case 'delete':
        // Un messaggio non partito c'è solo qui: si toglie senza chiedere.
        failed ? onDiscard() : onDelete();
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
          ?quote,
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
              child: message.failed
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 13,
                          color: MilanacColors.gold,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Non inviato · tocca per riprovare',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(message.createdAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                        // In invio: l'orologio finché il server non lo salva.
                        if (message.sending)
                          const Padding(
                            padding: EdgeInsets.only(left: 3),
                            child: Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: Colors.white54,
                            ),
                          ),
                      ],
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
              onTap: message.failed ? onRetry : null,
              onLongPress: () => _actions(context),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

/// Il messaggio citato dentro una bolla: tra quelli caricati, altrimenti (se è più
/// vecchio) chiesto al server; se è stato eliminato, "Messaggio non più disponibile".
class _Quote extends ConsumerWidget {
  const _Quote({
    required this.messageId,
    required this.loaded,
    required this.deleted,
    required this.nameOf,
    required this.mine,
  });
  final String messageId;
  final ChatMessage? loaded;
  final bool deleted;
  final String Function(String? authorId) nameOf;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var quoted = loaded;
    var text = 'Messaggio non più disponibile';
    if (quoted == null && !deleted) {
      final fetched = ref.watch(quotedMessageProvider(messageId));
      quoted = fetched.value;
      if (!fetched.hasValue) {
        text = fetched.hasError ? 'Citazione non caricata' : '…';
      }
    }
    return Container(
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
            quoted == null ? 'Messaggio precedente' : nameOf(quoted.authorId),
            style: const TextStyle(
              color: MilanacColors.gold,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          Text(
            quoted?.summary ?? text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// L'anteprima del replay letta da `meta.board` senza fidarsi: un valore malformato non
/// deve rompere (o bloccare, con coordinate enormi) la bolla per tutti.
BoardState _previewBoard(Object? raw) {
  if (raw is! Map) return const BoardState();
  try {
    final b = BoardState.fromJson(Map<String, dynamic>.from(raw));
    double fit(double v) => v.isFinite ? v.clamp(0.0, 1.0) : .5;
    return BoardState(
      module: b.module,
      team: b.team,
      tokens: [for (final t in b.tokens.take(60)) t.moved(fit(t.x), fit(t.y))],
      arrows: [
        for (final a in b.arrows.take(60))
          BoardArrow(
            x1: fit(a.x1),
            y1: fit(a.y1),
            x2: fit(a.x2),
            y2: fit(a.y2),
            dashed: a.dashed,
          ),
      ],
      heat: [for (final h in b.heat.take(300)) HeatPoint(fit(h.x), fit(h.y))],
    );
  } catch (_) {
    return const BoardState();
  }
}

/// Replay della lavagna: il campo con il pulsante Play (si riproduce nell'app).
class _ReplayBubble extends StatelessWidget {
  const _ReplayBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final board = _previewBoard(message.meta['board']);
    final title = message.replayTitle ?? 'Schema';
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
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(chatRepositoryProvider);
    final player = ref.read(voicePlayerProvider.notifier);
    void notice(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    final path = message.audioPath;
    if (path == null && message.isLocal) {
      notice('Il vocale si ascolta appena è inviato.');
      return;
    }
    try {
      final url = path == null ? '' : await repo.audioUrl(path);
      if (url.isEmpty) {
        notice('Vocale non disponibile nella demo.');
        return;
      }
      await player.toggle(message.id, url);
    } catch (e) {
      // Il lettore è tornato libero: toccando di nuovo si riprova.
      notice(friendlyError(e, action: 'Vocale non disponibile'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solo la bolla del vocale caricato si ridisegna a ogni scatto della posizione.
    final state = ref.watch(
      voicePlayerProvider.select((s) => s.playingId == message.id ? s : null),
    );
    final playing = state?.playing ?? false;
    final total = message.durationS ?? state?.duration?.inSeconds ?? 0;
    final shown = state == null ? total : state.position.inSeconds;
    final color = mine ? Colors.white : MilanacColors.gold;
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          IconButton.filled(
            tooltip: playing ? 'Pausa' : 'Ascolta',
            style: IconButton.styleFrom(
              backgroundColor: color,
              foregroundColor: mine ? MilanacColors.redDark : Colors.black,
            ),
            onPressed: () => _toggle(context, ref),
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
                    value: state?.progress ?? 0,
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

class _ChatImage extends ConsumerStatefulWidget {
  const _ChatImage({required this.message});
  final ChatMessage message;

  @override
  ConsumerState<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends ConsumerState<_ChatImage> {
  /// Dopo un errore il link firmato si rinnova una volta da solo (di solito era
  /// scaduto); poi resta il segnaposto, che si tocca per riprovare.
  bool _renewed = false;

  void _renew(String path) {
    if (mounted) ref.invalidate(chatImageUrlProvider(path));
  }

  Widget _unavailable(String path) {
    if (!_renewed) {
      _renewed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _renew(path));
    }
    return _ImageUnavailable(onRetry: () => _renew(path));
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final local = message.localImage;
    final Widget image;
    if (local != null) {
      image = Image.memory(local, fit: BoxFit.cover);
    } else {
      final path = message.imagePath!;
      final link = ref.watch(chatImageUrlProvider(path));
      final url = link.value;
      image = url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _unavailable(path),
            )
          : link.hasError
          ? _unavailable(path)
          : const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
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

/// Al posto di una foto che non si carica.
class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onRetry,
    child: Container(
      height: 120,
      width: 200,
      color: Colors.black26,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white54),
          SizedBox(height: 6),
          Text(
            'Foto non disponibile · tocca per riprovare',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
