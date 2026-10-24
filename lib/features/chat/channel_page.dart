import 'dart:async';
import 'dart:math' as math;

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
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart' show ContentWidth;
import '../../shared/async_view.dart';
import '../../shared/link_text.dart';
import '../../shared/member_photo.dart';
import '../../shared/ui.dart';
import '../carte/special_cards_repository.dart';
import '../formazione/formazione_page.dart' show formationPath;
import '../lavagna/board_model.dart';
import '../lavagna/board_painter.dart';
import '../lavagna/replay_pages.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'channel_messages.dart';
import 'chat_mentions.dart';
import 'chat_reactions.dart';
import 'chat_reads.dart';
import 'chat_repository.dart';
import 'chat_typing.dart';
import 'chat_widgets.dart';
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
    // Aperta da una notifica come unica pagina: indietro porta all'elenco dei canali
    // invece di chiudere l'app.
    return PopScope(
      canPop: !(ModalRoute.of(context)?.isFirst ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/chat');
      },
      child: channel != null
          // Una conversazione per canale: aprendo un altro canale (anche con
          // router.go, che riusa la pagina) si riparte da zero.
          ? _ChannelView(
              key: ValueKey(channel.id),
              channel: channel,
              openVoice: openVoice,
            )
          : Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: IconButton(
                  tooltip: 'Indietro',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => _exit(context),
                ),
                title: const Text('CHAT'),
                bottom: const _BarBorder(),
                flexibleSpace: const Align(
                  alignment: Alignment.topCenter,
                  child: GoldRule(),
                ),
              ),
              body: AsyncView<List<Channel>>(
                value: channels,
                onRetry: () => ref.invalidate(channelsProvider),
                action: 'Canali non caricati',
                data: (_) => _ChannelUnavailable(onExit: () => _exit(context)),
              ),
            ),
    );
  }
}

/// Il filo scuro sotto la barra in alto (sempre scura, come nelle sezioni).
class _BarBorder extends StatelessWidget implements PreferredSizeWidget {
  const _BarBorder();

  @override
  Size get preferredSize => const Size.fromHeight(1);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppPalette.dark.border,
    child: const SizedBox(height: 1, width: double.infinity),
  );
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

  /// La barra di scrittura: dopo una menzione scelta o "Rispondi" si continua a
  /// scrivere senza toccarla di nuovo.
  final _focus = FocusNode(debugLabel: 'chat-scrivi');
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

  /// Menzioni scelte dai suggerimenti (id → nome sulla carta) e quella che si sta
  /// scrivendo (la "@" prima del cursore).
  final _picked = <String, String>{};
  ({int start, String query})? _mention;

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

  /// "Sta scrivendo" del canale: resta aperto finché si guarda la conversazione (lo
  /// tiene vivo la barra in alto, che mostra chi scrive).
  TypingChannel? get _typing =>
      mounted ? ref.read(typingChannelProvider(_channel.id)) : null;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(voiceRecorderFactoryProvider)();
    _audioFocus = ref.read(audioFocusProvider.notifier);
    PushService.instance.shouldShowInApp = _pushFilter;
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      // Gli altri vedono "sta scrivendo" finché c'è testo.
      if (has) {
        _typing?.ping(TypingKind.testo);
      } else {
        _typing?.stop();
      }
      final mention = mentionAt(_text.text, _text.selection.baseOffset);
      if (mention != _mention) setState(() => _mention = mention);
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
    _focus.dispose();
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

  void _markRead(ChannelHistory history) {
    // Dopo una riconnessione mancano dei messaggi: si segna letto quando arrivano,
    // non prima (si segnerebbero anche quelli mai caricati).
    if (!_readBeforeLoaded || history.gap) return;
    // L'ora del server del messaggio più recente arrivato (quelli in invio da qui hanno
    // ancora l'ora del telefono, che può essere sbagliata).
    final newest = history.messages
        .where((m) => !m.isLocal)
        .firstOrNull
        ?.createdAt;
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
      // Un avviso alla volta: più messaggi scritti senza rete non ne accodano tanti.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
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
    final channel = _channel;
    // Le menzioni scelte e ancora scritte nel testo.
    final mentions = audio == null
        ? mentionsIn(body, _picked)
        : const <String>[];
    if (audio == null) _text.clear();
    setState(() {
      if (audio == null) {
        _image = null;
        _picked.clear();
        _mention = null;
      }
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
        meta: mentions.isEmpty ? null : {'mentions': mentions},
      ),
      channel,
    );
  }

  /// La menzione scelta dai suggerimenti prende il posto di quello che si era
  /// scritto dopo la "@".
  void _pickMention(Member m) {
    final mention = _mention;
    if (mention == null) return;
    final text = _text.text;
    final cursor = _text.selection.baseOffset.clamp(0, text.length);
    final insert = '@${m.displayName} ';
    _picked[m.id] = m.displayName;
    _text.value = TextEditingValue(
      text: text.replaceRange(mention.start, cursor, insert),
      selection: TextSelection.collapsed(offset: mention.start + insert.length),
    );
    _focus.requestFocus();
  }

  /// La propria reazione: la stessa emoji di nuovo la toglie.
  Future<void> _react(ChatMessage m, String emoji) async {
    final me = ref.read(currentUserIdProvider);
    final current =
        (ref.read(reactionsProvider(_channel.id)).value?[m.id] ??
                const <MessageReaction>[])
            .where((r) => r.userId == me)
            .firstOrNull;
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(chatRepositoryProvider)
          .react(m, current?.emoji == emoji ? null : emoji);
    } catch (e) {
      _notice(friendlyError(e, action: 'Reazione non salvata'));
    }
  }

  Future<void> _retry(ChatMessage m) async {
    final channel = _channel;
    _report(await _conversation.retry(m.id), channel);
  }

  /// Com'è andato un invio. L'invio continua anche uscendo dalla conversazione: se
  /// non parte lo si dice lo stesso, e il messaggio resta nel canale da riprovare.
  void _report(SendReport report, Channel channel) {
    final error = report.error;
    if (!mounted) {
      if (error != null) {
        showAppMessage(
          'Messaggio in ${channel.name} non inviato: riapri la conversazione '
          'e toccalo per riprovare.',
          duration: const Duration(seconds: 6),
        );
      }
      return;
    }
    if (report.quoteDropped) {
      _notice(
        'Il messaggio citato è stato eliminato: inviato senza citazione.',
      );
    }
    if (report.waiting) {
      _notice(
        'Senza rete: il messaggio partirà da solo appena torna, anche se '
        "chiudi l'app.",
      );
    }
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
    _typing?.ping(TypingKind.vocale);
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSeconds++);
      _typing?.ping(TypingKind.vocale);
      if (_recSeconds >= maxVoiceSeconds) _finishRecording(send: true);
    });
  }

  Future<void> _finishRecording({required bool send}) async {
    // Se il registratore sta ancora partendo ci pensa _startRecording.
    if (!_recording) return;
    _recTimer?.cancel();
    setState(() => _recording = false);
    _audioFocus.release(AudioUse.registrazioneVocale);
    _typing?.stop();
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

    final p = context.pal;
    // La barra in alto è sempre scura: colori fissi della tavola 13.
    const bar = AppPalette.dark;
    final typing = typingLabel(
      ref.watch(typistsProvider(channel.id)).value ?? const {},
      {
        for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
          m.id: m,
      },
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 60,
        titleSpacing: 0,
        leadingWidth: 52,
        leading: IconButton(
          tooltip: 'Indietro',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => ChannelPage._exit(context),
        ),
        title: Row(
          children: [
            ChannelTile(
              channel: channel,
              size: 38,
              radius: 12,
              highlighted: true,
              palette: bar,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: bodyFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: MilanacColors.ivory,
                    ),
                  ),
                  if (typing != null)
                    TypingText(
                      typing,
                      style: const TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        color: MilanacColors.goldLight,
                      ),
                    )
                  else
                    Text(
                      channel.audience,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                        color: bar.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          VoiceRoomButton(channel: channel),
          IconButton(
            tooltip: muted ? 'Riattiva le notifiche' : 'Silenzia il canale',
            icon: Icon(
              muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_none_rounded,
              size: 22,
              color: MilanacColors.ivoryMuted,
            ),
            onPressed: () => _toggleMute(muted),
          ),
          const SizedBox(width: 4),
        ],
        bottom: const _BarBorder(),
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
      ),
      body: ContentWidth(
        child: Column(
          children: [
            VoiceRoomBanner(channel: channel),
            Expanded(
              child: Stack(
                children: [
                  _messages(canWrite: canWrite),
                  if (_showJump)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        tooltip: 'Torna in fondo',
                        backgroundColor: p.surfaceHigh,
                        foregroundColor: p.text,
                        elevation: 1,
                        shape: CircleBorder(side: BorderSide(color: p.border)),
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
      ),
    );
  }

  /// [canWrite]: si può rispondere ai messaggi (in Comunicazioni solo il Direttivo).
  Widget _messages({required bool canWrite}) {
    final c = _channel;
    final me = ref.watch(profileProvider).value;
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final provider = messagesProvider(c.id);
    // Spunte e reazioni in tempo reale (senza: la conversazione resta com'era).
    final reads =
        ref.watch(channelReadsProvider(c.id)).value ??
        const <String, DateTime>{};
    final reactions =
        ref.watch(reactionsProvider(c.id)).value ??
        const <String, List<MessageReaction>>{};
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
          _markRead(history);
          _maybeLoadMore();
        });
        if (list.isEmpty && !history.hasMore) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                c.description ?? 'Scrivi il primo messaggio!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: context.pal.textMuted),
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
        // Nelle citazioni i propri messaggi sono "Tu".
        String quotedName(String? id) =>
            id != null && id == me?.id ? 'Tu' : nameOf(id);
        final showTop =
            history.hasMore || history.loadingMore || history.loadMoreFailed;
        // Lista al contrario: il più recente in basso.
        return KeyedSubtree(
          key: const ValueKey('chat-messaggi'),
          child: ListView.builder(
            key: _listKey,
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
              final mentioned = mentionIdsOf(m);
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
                                  nameOf: quotedName,
                                ),
                          canDelete:
                              !m.isLocal &&
                              (mine || (me?.isDirettivo ?? false)),
                          onReply: canWrite
                              ? () {
                                  setState(() => _replyTo = m);
                                  _focus.requestFocus();
                                }
                              : null,
                          onDelete: () => _confirmDelete(m),
                          onRetry: () => _retry(m),
                          onDiscard: () =>
                              ref.read(provider.notifier).discard(m.id),
                          readBy: mine && !m.isLocal
                              ? readersOf(m, reads).length
                              : 0,
                          reactions: reactions[m.id] ?? const [],
                          me: me?.id,
                          onReact: (emoji) => _react(m, emoji),
                          onShowReactions: () => showReactionsSheet(
                            context,
                            reactions: reactions[m.id] ?? const [],
                            members: members,
                            me: me?.id,
                          ),
                          onInfo: mine && !m.isLocal
                              ? () => showMessageInfo(
                                  context,
                                  message: m,
                                  readers: readersOf(m, reads),
                                  audience: channelAudience(c, members.values),
                                )
                              : null,
                          highlights: [
                            for (final id in mentioned)
                              if (members[id] != null)
                                '@${members[id]!.displayName}',
                          ],
                          mentionsMe: me != null && mentioned.contains(me.id),
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
    final p = context.pal;
    OutlineInputBorder pill(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    // Barra di scrittura della tavola 13: foto, "Scrivi un messaggio", microfono
    // (tieni premuto) o invio.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mention case final mention?)
                if (mentionCandidates(
                      mention.query,
                      channelAudience(
                        _channel,
                        ref.watch(rosaProvider).value ?? const <Member>[],
                      ),
                      me: ref.watch(currentUserIdProvider),
                    )
                    case final candidates when candidates.isNotEmpty)
                  MentionSuggestions(
                    candidates: candidates,
                    onPick: _pickMention,
                  ),
              if (_replyTo != null)
                _ReplyStrip(
                  message: _replyTo!,
                  title: _replyTo!.authorId == ref.watch(currentUserIdProvider)
                      ? 'Rispondi al tuo messaggio'
                      : 'Rispondi a ${members[_replyTo!.authorId] ?? 'Ex membro'}',
                  onClose: () => setState(() => _replyTo = null),
                ),
              if (_image != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          // Anteprima alta 90: decodificata a quell'altezza.
                          child: Image.memory(
                            _image!,
                            height: 90,
                            cacheHeight:
                                (90 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton.filled(
                          tooltip: 'Togli la foto',
                          style: IconButton.styleFrom(
                            backgroundColor: p.surfaceHigher,
                            foregroundColor: p.text,
                            minimumSize: const Size(32, 32),
                            fixedSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () => setState(() => _image = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
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
                      tooltip: 'Aggiungi una foto',
                      onPressed: _pickImage,
                      icon: Icon(
                        Icons.image_rounded,
                        size: 22,
                        color: p.textSecondary,
                      ),
                    ),
                  Expanded(
                    child: _recording
                        ? _RecordingIndicator(
                            seconds: _recSeconds,
                            cancelling: _recCancel,
                          )
                        : Semantics(
                            label: 'Messaggio',
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 2000,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(fontSize: 16, color: p.text),
                              decoration: InputDecoration(
                                hintText: 'Scrivi un messaggio',
                                counterText: '',
                                isDense: true,
                                filled: true,
                                fillColor: p.surfaceHigh,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 11,
                                ),
                                border: pill(p.borderStrong),
                                enabledBorder: pill(p.borderStrong),
                                focusedBorder: pill(p.chipBorder),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  if (canSend && !_recording)
                    _RoundAction(
                      tooltip: 'Invia',
                      icon: Icons.send_rounded,
                      onPressed: () => _send(),
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
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: p.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Canale non disponibile',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: p.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Non esiste più oppure non è tra quelli che puoi vedere.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: p.textSecondary),
            ),
            const SizedBox(height: 20),
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

/// Pulsante tondo oro della barra di scrittura (invia).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size(48, 48),
        fixedSize: const Size(48, 48),
      ),
      icon: Icon(icon, size: 22),
    );
  }
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
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: 'Tieni premuto per registrare un vocale',
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: (_) => onStart(),
        onLongPressMoveUpdate: (d) => onMove(d.offsetFromOrigin.dx),
        onLongPressEnd: (_) => onEnd(),
        onLongPressCancel: onCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: recording ? 56 : 48,
          height: recording ? 56 : 48,
          decoration: BoxDecoration(
            color: p.accent,
            shape: BoxShape.circle,
            boxShadow: recording
                ? [
                    BoxShadow(
                      color: p.accent.withValues(alpha: .45),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.mic_rounded,
            color: p.onAccent,
            size: recording ? 26 : 22,
          ),
        ),
      ),
    );
  }
}

/// Al posto del campo di testo mentre si registra: punto rosso, durata e istruzioni.
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.seconds, required this.cancelling});
  final int seconds;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(Icons.circle, size: 12, color: p.danger),
          const SizedBox(width: 8),
          Text(
            formatSeconds(seconds),
            style: TextStyle(
              fontFamily: sportFont,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: p.text,
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
                color: cancelling ? p.danger : p.textMuted,
                fontSize: 14,
                fontWeight: cancelling ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Sopra il campo di testo: il messaggio a cui si sta rispondendo.
class _ReplyStrip extends StatelessWidget {
  const _ReplyStrip({
    required this.message,
    required this.title,
    required this.onClose,
  });
  final ChatMessage message;

  /// "Rispondi a Marco Rossi" (o "al tuo messaggio").
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: p.accentText, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 18, color: p.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.accentText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  message.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Annulla risposta',
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, size: 18, color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Canale in sola lettura (Comunicazioni): vi scrive solo il Direttivo.
class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: p.accentText, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Qui scrive solo il Direttivo: avvisi ufficiali, formazioni ed eventi.',
                  style: TextStyle(color: p.textSecondary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Separatore per giorno: pillola al centro ("Oggi", "Ieri", "Lunedì 12 ottobre").
class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final long = DateFormat(
      d.year == today.year ? 'EEEE d MMMM' : 'EEEE d MMMM y',
      'it',
    ).format(day);
    final label = d == today
        ? 'Oggi'
        : d == today.subtract(const Duration(days: 1))
        ? 'Ieri'
        : '${long[0].toUpperCase()}${long.substring(1)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: p.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
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
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget line() => Expanded(child: Container(height: 1, color: p.chipBorder));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Nuovi messaggi',
              style: TextStyle(
                color: p.accentText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          line(),
        ],
      ),
    );
  }
}

/// Messaggio automatico (formazione pubblicata, carte speciali, nuovo ingresso nel
/// club...): al centro; un tocco apre la pagina di cui parla.
class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final type = message.systemType;
    final gold = type == 'formation' || type == 'special_cards';
    final icon = switch (type) {
      'formation' => Icons.sports_soccer_rounded,
      'special_cards' => Icons.military_tech_rounded,
      'new_member' => Icons.person_add_alt_1_rounded,
      _ => Icons.info_rounded,
    };
    // Pagine dentro le schede, mentre la conversazione sta sopra: ci si va con go
    // (push farebbe una seconda copia delle schede).
    final route = switch (type) {
      // La formazione della squadra del messaggio (se manca, quella del giocatore).
      'formation' => formationPath(Team.parse(message.meta['team'])),
      'special_cards' => '/carte-speciali',
      'new_member' => '/rosa',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Center(
        child: Material(
          color: gold ? p.accentTint : p.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: gold ? p.accentTintBorder : p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: route == null ? null : () => context.go(route),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: gold ? p.accentText : p.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message.body ?? '',
                      style: TextStyle(fontSize: 14, color: p.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('HH:mm').format(message.createdAt),
                    style: TextStyle(fontSize: 12, color: p.textMuted),
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

/// Bolla di un messaggio (tavola 13): le mie a destra in oro tenue, quelle degli
/// altri a sinistra con volto e nome; dentro citazione, foto, vocale, testo e ora.
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
    this.readBy = 0,
    this.reactions = const [],
    this.me,
    this.onReact,
    this.onShowReactions,
    this.onInfo,
    this.highlights = const [],
    this.mentionsMe = false,
  });
  final ChatMessage message;
  final Member? author;
  final String authorName;
  final bool mine;
  final bool showAuthor;
  final bool canDelete;

  /// null se nel canale non si può scrivere (Comunicazioni per chi non è del
  /// Direttivo): niente "Rispondi".
  final VoidCallback? onReply;
  final VoidCallback onDelete;

  /// Messaggio non partito: si riprova o si toglie.
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// Il messaggio citato (se risponde a un altro).
  final Widget? quote;

  /// Quanti l'hanno letto (solo i propri messaggi): una spunta se nessuno, due dorate
  /// se almeno uno.
  final int readBy;

  /// Le reazioni al messaggio e chi guarda (per riconoscere la propria).
  final List<MessageReaction> reactions;
  final String? me;
  final ValueChanged<String>? onReact;
  final VoidCallback? onShowReactions;

  /// "Info" (chi l'ha letto): solo per i propri messaggi già salvati.
  final VoidCallback? onInfo;

  /// Le menzioni da evidenziare nel testo ("@ROSSI"); [mentionsMe] se c'è anche la
  /// propria (la bolla ha il bordo dorato).
  final List<String> highlights;
  final bool mentionsMe;

  Future<void> _actions(BuildContext context) async {
    // Non partito, o fermo per la rete: si rimanda subito o si toglie.
    final failed = message.failed || message.waiting;
    final reply = onReply;
    final canReply = reply != null && !message.isLocal;
    final canCopy = message.hasText;
    final canRemove = failed || canDelete;
    final canReact = !message.isLocal && onReact != null;
    if (!failed && !canReply && !canCopy && !canRemove && !canReact) return;
    HapticFeedback.mediumImpact();
    final myReaction = reactions
        .where((r) => r.userId == me)
        .firstOrNull
        ?.emoji;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReact) ...[
              ReactionPicker(
                current: myReaction,
                onPick: (emoji) => Navigator.pop(c, 'react:$emoji'),
              ),
              const Divider(height: 12),
            ],
            if (failed)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: Text(message.waiting ? 'Invia adesso' : 'Riprova'),
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
            if (onInfo != null)
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Info: chi l\'ha letto'),
                onTap: () => Navigator.pop(c, 'info'),
              ),
            if (canRemove)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: c.pal.danger,
                ),
                title: Text(
                  'Elimina messaggio',
                  style: TextStyle(color: c.pal.danger),
                ),
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
        reply?.call();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body!));
      case 'delete':
        // Un messaggio non partito c'è solo qui: si toglie senza chiedere.
        failed ? onDiscard() : onDelete();
      case 'info':
        onInfo?.call();
      case final picked? when picked.startsWith('react:'):
        onReact?.call(picked.substring('react:'.length));
    }
  }

  /// Ora (con l'orologio finché è in invio), "In attesa di rete" oppure "Non
  /// inviato".
  Widget _status(AppPalette p) {
    if (message.waiting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 14, color: p.warning),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'In attesa di rete · parte da solo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.warning,
              ),
            ),
          ),
        ],
      );
    }
    if (message.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: p.danger),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Non inviato · tocca per riprovare',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.danger,
              ),
            ),
          ),
        ],
      );
    }
    final color = mine ? p.textSecondary : p.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('HH:mm').format(message.createdAt),
          style: TextStyle(fontSize: 12, color: color),
        ),
        if (message.sending)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.schedule_rounded,
              size: 12,
              color: color,
              semanticLabel: 'in invio',
            ),
          )
        else if (mine)
          // Una spunta: arrivato. Due dorate: letto da almeno uno.
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Icon(
              readBy > 0 ? Icons.done_all_rounded : Icons.done_rounded,
              size: 15,
              color: readBy > 0 ? p.accentText : color,
              semanticLabel: readBy > 0
                  ? 'letto da $readBy'
                  : 'inviato, non ancora letto',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    // Chi ha la carta speciale della settimana ha l'anello colorato sul volto.
    final special = author == null
        ? null
        : ref.watch(activeSpecialCardProvider(author!.id));
    final screen = math.min(
      MediaQuery.sizeOf(context).width,
      ContentWidth.maxWidth,
    );
    final maxWidth = screen * (mine ? .70 : .67);
    // Solo una, due o tre emoji: grandi e senza bolla, come su WhatsApp.
    final big =
        isEmojiOnly(message.body) &&
        !message.hasImage &&
        !message.hasAudio &&
        !message.isReplay &&
        !message.isAnnouncement &&
        quote == null;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.fromLTRB(12, mine ? 9 : 8, 12, mine ? 7 : 6),
      decoration: BoxDecoration(
        color: big
            ? Colors.transparent
            : mine
            ? p.accentTint
            : p.surfaceHigh,
        border: Border.all(
          color: big
              ? Colors.transparent
              : message.isAnnouncement || mentionsMe
              ? p.importantBorder
              : mine
              ? p.accentTintBorder
              : p.border,
          width: message.isAnnouncement || mentionsMe ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      // La bolla si stringe sul contenuto più largo; citazione e avvisi la riempiono
      // e l'ora resta in fondo a destra.
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isAnnouncement)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.campaign_rounded, size: 16, color: p.accentText),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'AVVISO DEL DIRETTIVO',
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
              ),
            if (showAuthor && !mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.accentText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ?quote,
            if (message.isReplay)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ReplayBubble(message: message),
              ),
            if (message.hasImage)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ChatImage(message: message, width: maxWidth - 24),
              ),
            if (message.hasAudio && !message.isReplay)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _VoiceBubble(message: message),
              ),
            if (message.isExpired)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ExpiredChip(message: message),
              ),
            if (message.hasText)
              LinkText(
                message.body!,
                style: TextStyle(
                  fontSize: big ? 44 : 16,
                  color: p.text,
                  height: big ? 1.15 : 1.3,
                ),
                linkColor: p.accentText,
                highlights: highlights,
                highlightStyle: TextStyle(color: p.accentText),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _status(p),
              ),
            ),
          ],
        ),
      ),
    );
    final who = author;
    final Widget? face = mine || !showAuthor
        ? null
        : who == null
        ? CircleAvatar(
            radius: 16,
            backgroundColor: p.surfaceHigher,
            child: Icon(Icons.person_rounded, size: 18, color: p.textMuted),
          )
        : special == null
        ? MemberAvatar(member: who, radius: 16, showNumber: false)
        : Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: special.kind.color, width: 2),
            ),
            child: MemberAvatar(member: who, radius: 12, showNumber: false),
          );
    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 10 : 4),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            // Con le reazioni sotto, il volto resta all'altezza della bolla.
            Padding(
              padding: EdgeInsets.only(bottom: reactions.isEmpty ? 0 : 32),
              child: SizedBox(width: 32, child: face),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwipeToReply(
                  onReply: message.isLocal ? null : onReply,
                  child: GestureDetector(
                    onTap: message.failed || message.waiting ? onRetry : null,
                    onLongPress: () => _actions(context),
                    child: bubble,
                  ),
                ),
                if (reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ReactionChips(
                      reactions: reactions,
                      me: me,
                      alignEnd: mine,
                      onToggle: (emoji) => onReact?.call(emoji),
                      onShowWho: () => onShowReactions?.call(),
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

/// Trascinando la bolla verso destra si risponde, come su WhatsApp: la freccia compare
/// man mano, oltre la soglia il telefono vibra e al rilascio parte la risposta.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.onReply, required this.child});

  /// null: niente risposta (canale in sola lettura, messaggio non ancora partito).
  final VoidCallback? onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _max = 72.0;
  static const _trigger = 56.0;
  double _dx = 0;
  double _from = 0;
  bool _armed = false;
  late final AnimationController _back =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 180),
      )..addListener(() {
        setState(
          () => _dx = _from * (1 - Curves.easeOut.transform(_back.value)),
        );
      });

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _back.stop();
    final dx = (_dx + d.delta.dx).clamp(0.0, _max);
    final armed = dx >= _trigger;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _dx = dx;
      _armed = armed;
    });
  }

  void _end() {
    if (_armed) widget.onReply?.call();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final p = context.pal;
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: _end,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 0)
            Positioned(
              left: _dx / 2 - 18,
              child: Opacity(
                opacity: (_dx / _trigger).clamp(0.0, 1.0),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: _armed ? p.accent : p.surfaceHigher,
                  child: Icon(
                    Icons.reply_rounded,
                    size: 18,
                    color: _armed ? p.onAccent : p.textSecondary,
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
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
  });
  final String messageId;
  final ChatMessage? loaded;
  final bool deleted;
  final String Function(String? authorId) nameOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.surfaceHigher,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quoted == null ? 'Messaggio precedente' : nameOf(quoted.authorId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Text(
            quoted?.summary ?? text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.textSecondary, fontSize: 14),
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
    final p = context.pal;
    final board = _previewBoard(message.meta['board']);
    final title = message.replayTitle ?? 'Schema';
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.draw_rounded, size: 16, color: p.accentText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'SCHEMA CON AUDIO',
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
          Stack(
            alignment: Alignment.center,
            children: [
              BoardPreview(state: board),
              if (!message.isExpired)
                IconButton.filled(
                  tooltip: 'Riproduci il replay',
                  style: IconButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
          if (message.durationS != null && !message.isExpired)
            Text(
              '${formatSeconds(message.durationS!)} · scade dopo 3 giorni',
              style: TextStyle(color: p.textMuted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// L'allegato è scaduto (foto e vocali dopo 60 giorni, schemi dopo 3).
class _ExpiredChip extends StatelessWidget {
  const _ExpiredChip({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Il file non c'è più: la durata, che resta, dice se era un vocale.
    final (icon, text) = message.isReplay
        ? (Icons.draw_rounded, 'Schema scaduto')
        : message.durationS != null
        ? (Icons.mic_off_rounded, 'Vocale scaduto')
        : (Icons.image_rounded, 'Foto scaduta');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surfaceHigher,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: p.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Messaggio vocale: ascolta/pausa, forma d'onda (oro fin dove si è ascoltato) e
/// durata.
class _VoiceBubble extends ConsumerWidget {
  const _VoiceBubble({required this.message});
  final ChatMessage message;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final player = ref.read(voicePlayerProvider.notifier);
    void notice(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    final path = message.audioPath;
    if (path == null && message.isLocal) {
      notice('Il vocale si ascolta appena è inviato.');
      return;
    }
    try {
      // Il link firmato serve solo per caricare il vocale, e resta in memoria:
      // pausa e ripresa di quello già nel lettore non lo chiedono (vanno anche
      // senza rete).
      await player.toggle(message.id, () async {
        final url = path == null
            ? ''
            : await ref.read(chatAudioUrlProvider(path).future);
        if (url.isEmpty) {
          throw const AppError('Vocale non disponibile nella demo.');
        }
        return url;
      });
    } catch (e) {
      // Il lettore è tornato libero: toccando di nuovo si riprova.
      notice(friendlyError(e, action: 'Vocale non disponibile'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    // Solo la bolla del vocale caricato si ridisegna a ogni scatto della posizione.
    final state = ref.watch(
      voicePlayerProvider.select((s) => s.playingId == message.id ? s : null),
    );
    final playing = state?.playing ?? false;
    final loading = state?.loading ?? false;
    final total = message.durationS ?? state?.duration?.inSeconds ?? 0;
    final shown = state == null ? total : state.position.inSeconds;
    return SizedBox(
      width: 206,
      child: Row(
        children: [
          IconButton.filled(
            tooltip: loading
                ? 'Annulla il caricamento'
                : playing
                ? 'Metti in pausa'
                : 'Ascolta il vocale',
            style: IconButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              minimumSize: const Size(40, 40),
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => _toggle(context, ref),
            icon: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: p.onAccent,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 22,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeSemantics(
              child: SizedBox(
                height: 28,
                child: CustomPaint(
                  painter: _Waveform(
                    seed: message.id.codeUnits.fold(
                      7,
                      (h, c) => (h * 31 + c) % 2147483647,
                    ),
                    progress: state?.progress ?? 0,
                    played: p.accentText,
                    idle: p.isDark ? p.outline : p.textDisabled,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(
              formatSeconds(shown),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forma d'onda del vocale: barre di altezza fissa per messaggio (non c'è l'onda
/// vera), in oro fin dove si è ascoltato.
class _Waveform extends CustomPainter {
  const _Waveform({
    required this.seed,
    required this.progress,
    required this.played,
    required this.idle,
  });
  final int seed;
  final double progress;
  final Color played;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = 3.0, gap = 3.0;
    final count = ((size.width + gap) / (bar + gap)).floor();
    final paint = Paint();
    var x = seed % 2147483647;
    if (x <= 0) x += 2147483646;
    for (var i = 0; i < count; i++) {
      x = (x * 48271) % 2147483647;
      final h = 8.0 + x % 19;
      paint.color = i < progress * count ? played : idle;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (bar + gap), (size.height - h) / 2, bar, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Waveform old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.played != played ||
      old.idle != idle;
}

class _ChatImage extends ConsumerStatefulWidget {
  const _ChatImage({required this.message, required this.width});
  final ChatMessage message;

  /// Larghezza della foto nella bolla.
  final double width;

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
    // Nella bolla la foto si decodifica alla larghezza in cui si vede, non a quella
    // della foto intera: con tante foto la chat resta leggera anche sui telefoni
    // economici. A schermo intero (con lo zoom) arriva intera.
    final cacheWidth = math.max(
      1,
      (widget.width * MediaQuery.devicePixelRatioOf(context)).round(),
    );
    final Widget image;
    final Widget full;
    if (local != null) {
      image = Image.memory(local, fit: BoxFit.cover, cacheWidth: cacheWidth);
      full = Image.memory(local);
    } else {
      final path = message.imagePath!;
      final link = ref.watch(chatImageUrlProvider(path));
      final url = link.value;
      if (url != null && url.isNotEmpty) {
        image = Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          errorBuilder: (_, _, _) => _unavailable(path),
        );
        // Se quella intera non arriva resta quella della bolla.
        full = Image.network(url, errorBuilder: (_, _, _) => image);
      } else {
        full = image = link.hasError
            ? _unavailable(path)
            : const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
      }
    }
    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: MilanacColors.black,
            appBar: AppBar(backgroundColor: MilanacColors.black),
            body: Center(child: InteractiveViewer(maxScale: 5, child: full)),
          ),
        ),
      ),
      child: SizedBox(
        width: widget.width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: image,
          ),
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
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        height: 120,
        color: p.surfaceHigher,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_rounded, color: p.textMuted),
            const SizedBox(height: 6),
            Text(
              'Foto non disponibile · tocca per riprovare',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
