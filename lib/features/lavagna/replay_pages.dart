import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_focus.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart' show ContentWidth;
import '../../shared/async_view.dart';
import '../../shared/gold_loader.dart';
import '../../shared/ui.dart';
import '../chat/chat_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'board_model.dart';
import 'full_page.dart';
import 'replay_player.dart';

/// Dopo la registrazione: si riguarda il replay e lo si manda in una chat, oppure si butta.
class ReplayPreviewPage extends ConsumerStatefulWidget {
  const ReplayPreviewPage({
    super.key,
    required this.data,
    required this.title,
    this.audioBytes,
    this.audioPath,
    this.seconds,
  });
  final ReplayData data;
  final String title;
  final Uint8List? audioBytes;
  final String? audioPath;
  final int? seconds;

  @override
  ConsumerState<ReplayPreviewPage> createState() => _ReplayPreviewPageState();
}

class _ReplayPreviewPageState extends ConsumerState<ReplayPreviewPage> {
  late final ReplayPlayer _player;
  late final _title = TextEditingController(text: widget.title);
  String? _channelId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _player = ReplayPlayer(
      widget.data,
      audioFile: widget.audioPath,
      focus: ref.read(audioFocusProvider.notifier),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _title.dispose();
    _deleteTemp();
    super.dispose();
  }

  void _deleteTemp() {
    final p = widget.audioPath;
    if (p == null) return;
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  Future<void> _send(List<Channel> channels) async {
    final channel = channels
        .where((c) => c.id == (_channelId ?? ''))
        .firstOrNull;
    if (channel == null) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await _player.pause();
      final title = _title.text.trim();
      await ref
          .read(chatRepositoryProvider)
          .send(
            channel.id,
            audio: widget.audioBytes,
            durationS: widget.seconds ?? (widget.data.durationMs / 1000).ceil(),
            replay: widget.data.toBytes(),
            meta: {
              'type': 'replay',
              'title': title.isEmpty ? 'Schema' : title,
              'board': widget.data.initial.toPreviewJson(),
              'duration_ms': widget.data.durationMs,
            },
          );
      messenger.showSnackBar(
        SnackBar(content: Text('Replay inviato in ${channel.name}.')),
      );
      if (mounted) nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Invio non riuscito'))),
      );
    }
  }

  /// Indietro senza aver inviato: il replay si perderebbe, quindi si chiede.
  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminare il replay?'),
        content: const Text('Non è stato inviato: uscendo andrà perso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: dangerButtonStyle(c),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true && mounted && !_sending) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    // Un altro prende l'audio (un vocale, una chiamata...): il replay va in pausa.
    ref.listen(audioFocusProvider, (_, uses) {
      if (!uses.contains(AudioUse.replay)) _player.pause();
    });
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final channels = (ref.watch(channelsProvider).value ?? const <Channel>[])
        .where((c) => !c.direttivoWrites || isDirettivo)
        .toList();
    _channelId ??=
        channels.where((c) => c.slug == 'tattiche').firstOrNull?.id ??
        channels.firstOrNull?.id;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Durante l'invio si resta qui: alla fine la pagina si chiude da sola.
        if (!didPop && !_sending) _confirmLeave();
      },
      child: Scaffold(
        appBar: fullPageBar(context, title: 'ANTEPRIMA DEL REPLAY'),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ReplayView(player: _player),
              const SizedBox(height: 20),
              const SectionLabel('Invia in chat'),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Titolo dello schema',
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _channelId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Invia nel canale',
                ),
                items: [
                  for (final c in channels)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _channelId = v),
              ),
              const SizedBox(height: 8),
              Text(
                'Il replay resta in chat per 3 giorni, poi sparisce da solo.',
                style: TextStyle(fontSize: 14, color: context.pal.textMuted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _sending || _channelId == null
                    ? null
                    : () => _send(channels),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Invia in chat'),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _sending
                    ? null
                    : () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: context.pal.danger,
                  minimumSize: const Size(64, 48),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Elimina'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il replay arrivato in chat, a schermo intero: scarica azioni e audio e li riproduce.
class ReplayPage extends ConsumerStatefulWidget {
  const ReplayPage({super.key, required this.message});
  final ChatMessage message;

  @override
  ConsumerState<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends ConsumerState<ReplayPage> {
  late final AudioFocus _focus;
  ReplayPlayer? _player;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _focus = ref.read(audioFocusProvider.notifier);
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      final bytes = await repo.replayBytes(widget.message);
      if (bytes == null) {
        throw const AppError(
          'Il replay non è più disponibile: dopo 3 giorni sparisce dalla chat.',
        );
      }
      final data = ReplayData.fromBytes(bytes);
      final audioPath = widget.message.audioPath;
      final url = audioPath == null ? '' : await repo.audioUrl(audioPath);
      if (!mounted) return;
      setState(() {
        _player = ReplayPlayer(
          data,
          audioUrl: url.isEmpty ? null : url,
          focus: _focus,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Un altro prende l'audio (un vocale, una chiamata...): il replay va in pausa.
    ref.listen(audioFocusProvider, (_, uses) {
      if (!uses.contains(AudioUse.replay)) _player?.pause();
    });
    final m = widget.message;
    final author = ref
        .watch(rosaProvider)
        .value
        ?.where((x) => x.id == m.authorId)
        .firstOrNull;
    final error = _error;
    final p = context.pal;
    return Scaffold(
      appBar: fullPageBar(context, title: 'REPLAY DELLA LAVAGNA'),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              (m.replayTitle ?? 'Schema').toUpperCase(),
              style: TextStyle(
                fontFamily: sportFont,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
                color: p.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _authorLine(author),
              style: TextStyle(fontSize: 14, color: p.textMuted),
            ),
            const SizedBox(height: 14),
            if (error != null)
              ErrorRetry(
                message: friendlyError(error, action: 'Replay non disponibile'),
                onRetry: error is AppError ? null : _retry,
              )
            else if (_player == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: GoldLoader()),
              )
            else
              ReplayView(player: _player!),
          ],
        ),
      ),
    );
  }

  String _authorLine(Member? author) {
    final who = author?.displayName ?? 'Direttivo';
    final secs = widget.message.durationS;
    return secs == null
        ? 'di $who'
        : 'di $who · ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }
}
