import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../chat/chat_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'board_model.dart';
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
  late final _player = ReplayPlayer(widget.data, audioFile: widget.audioPath);
  late final _title = TextEditingController(text: widget.title);
  String? _channelId;
  bool _sending = false;

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
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text('Invio non riuscito: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final channels = (ref.watch(channelsProvider).value ?? const <Channel>[])
        .where((c) => !c.direttivoWrites || isDirettivo)
        .toList();
    _channelId ??= channels
        .where((c) => c.slug == 'tattiche')
        .firstOrNull
        ?.id ??
        channels.firstOrNull?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('ANTEPRIMA DEL REPLAY')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ReplayView(player: _player),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Titolo dello schema'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _channelId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Invia nel canale'),
            items: [
              for (final c in channels)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _channelId = v),
          ),
          const SizedBox(height: 8),
          const Text(
            'Il replay resta in chat per 3 giorni, poi sparisce da solo.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending || _channelId == null
                ? null
                : () => _send(channels),
            icon: const Icon(Icons.send_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Invia in chat'),
            ),
          ),
          TextButton.icon(
            onPressed: _sending ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            label: const Text(
              'Elimina',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
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
  ReplayPlayer? _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      final bytes = await repo.replayBytes(widget.message);
      if (bytes == null) throw Exception('replay non disponibile');
      final data = ReplayData.fromBytes(bytes);
      final audioPath = widget.message.audioPath;
      final url = audioPath == null ? '' : await repo.audioUrl(audioPath);
      if (!mounted) return;
      setState(() {
        _player = ReplayPlayer(data, audioUrl: url.isEmpty ? null : url);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Replay non disponibile: $e');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final author = ref
        .watch(rosaProvider)
        .value
        ?.where((x) => x.id == m.authorId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('REPLAY DELLA LAVAGNA')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            (m.meta['title'] as String?) ?? 'Schema',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            _authorLine(author),
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: MilanacColors.redText))
          else if (_player == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ReplayView(player: _player!),
        ],
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
