import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import 'clip_service.dart';
import 'clip_trim_page.dart';
import 'match.dart';
import 'match_editor.dart';
import 'matches_repository.dart';
import 'media_viewer.dart';
import 'risultati_page.dart';

class MatchDetailPage extends ConsumerWidget {
  const MatchDetailPage({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final match = ref
        .watch(matchesProvider)
        .value
        ?.where((m) => m.id == matchId)
        .firstOrNull;
    final media = ref.watch(matchMediaProvider(matchId));

    if (match == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Partita non trovata.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          match.kind == MatchKind.torneo ? 'PARTITA UFFICIALE' : 'AMICHEVOLE',
        ),
        actions: [
          if (isDirettivo) ...[
            IconButton(
              tooltip: 'Modifica partita',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => showMatchEditor(context, match: match),
            ),
            IconButton(
              tooltip: 'Elimina partita',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  'Eliminare la partita e tutti i suoi media?',
                );
                if (ok != true) return;
                await ref.read(matchesRepositoryProvider).delete(match.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
      floatingActionButton: isDirettivo
          ? FloatingActionButton.extended(
              backgroundColor: MilanacColors.red,
              onPressed: () => _addMedia(context, ref, match.id),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Aggiungi media'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          MatchCard(match: match),
          if (match.notes != null && match.notes!.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(match.notes!, style: const TextStyle(height: 1.4)),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              'GOL E HIGHLIGHTS',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
          ),
          media.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Errore: $e'),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Nessun video o foto per questa partita.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.9,
                    children: [
                      for (final m in items)
                        _MediaTile(media: m, canDelete: isDirettivo),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirm(BuildContext context, String text) => showDialog<bool>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(text),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c, false),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(c, true),
        child: const Text('Conferma'),
      ),
    ],
  ),
);

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.media, required this.canDelete});
  final MatchMedia media;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ytId = media.type == MediaType.link
        ? youtubeId(media.url ?? '')
        : null;
    final (icon, label) = switch (media.type) {
      MediaType.photo => (Icons.photo_rounded, 'Foto'),
      MediaType.video => (
        Icons.play_circle_fill_rounded,
        'Clip ${media.durationS ?? ''}s',
      ),
      MediaType.link => (Icons.link_rounded, ytId != null ? 'YouTube' : 'Link'),
    };

    Widget preview;
    if (media.type == MediaType.photo) {
      preview = MediaImage(media: media, fit: BoxFit.cover);
    } else if (ytId != null) {
      preview = Image.network(
        'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      preview = Container(color: MilanacColors.surfaceHigh);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => openMedia(context, media),
        onLongPress: canDelete
            ? () async {
                final ok = await _confirm(
                  context,
                  'Eliminare questo contenuto?',
                );
                if (ok == true) {
                  await ref.read(matchesRepositoryProvider).deleteMedia(media);
                }
              }
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview,
            if (media.type != MediaType.photo)
              Center(
                child: Icon(
                  icon,
                  size: 48,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Text(
                  media.caption ?? label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openMedia(BuildContext context, MatchMedia media) async {
  if (media.type == MediaType.link) {
    await launchUrl(
      Uri.parse(media.url!),
      mode: LaunchMode.externalApplication,
    );
    return;
  }
  await Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute(builder: (_) => MediaViewer(media: media)));
}

/// Scelta del tipo di contenuto da allegare: link, foto o clip da max 15 secondi.
Future<void> _addMedia(
  BuildContext context,
  WidgetRef ref,
  String matchId,
) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Link a un video'),
            subtitle: const Text('YouTube, Twitch, Instagram, TikTok…'),
            onTap: () => Navigator.pop(c, 'link'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Foto dalla galleria'),
            onTap: () => Navigator.pop(c, 'photo'),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_rounded),
            title: const Text('Clip highlights (max 15 secondi)'),
            subtitle: Text(
              ClipService.isSupported
                  ? 'Dalla galleria: scegli tu da dove iniziare'
                  : "Disponibile solo nell'app Android/iOS",
            ),
            enabled: ClipService.isSupported,
            onTap: () => Navigator.pop(c, 'video'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_rounded),
            title: const Text('Registra clip (max 15 secondi)'),
            enabled: ClipService.isSupported,
            onTap: () => Navigator.pop(c, 'camera'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final repo = ref.read(matchesRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (choice) {
      case 'link':
        final result = await _askLink(context);
        if (result == null) return;
        await repo.addLink(matchId, result.$1, caption: result.$2);
      case 'photo':
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 80,
        );
        if (file == null) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Caricamento foto…')),
        );
        await repo.uploadMedia(
          matchId,
          type: MediaType.photo,
          bytes: await file.readAsBytes(),
          extension: 'jpg',
        );
      case 'video' || 'camera':
        final file = await ImagePicker().pickVideo(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxDuration: const Duration(seconds: maxClipSeconds),
        );
        if (file == null || !context.mounted) return;
        final clip = await Navigator.of(context, rootNavigator: true)
            .push<PreparedClip>(
              MaterialPageRoute(builder: (_) => ClipTrimPage(path: file.path)),
            );
        if (clip == null) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Caricamento clip…')),
        );
        await repo.uploadMedia(
          matchId,
          type: MediaType.video,
          bytes: clip.bytes,
          extension: 'mp4',
          durationS: clip.durationS,
        );
    }
    messenger.showSnackBar(const SnackBar(content: Text('Contenuto aggiunto')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Caricamento non riuscito: $e')),
    );
  }
}

Future<(String, String?)?> _askLink(BuildContext context) =>
    showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _url = TextEditingController();
  final _caption = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _caption.dispose();
    super.dispose();
  }

  void _submit() {
    var url = _url.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';
    final caption = _caption.text.trim();
    Navigator.pop(context, (url, caption.isEmpty ? null : caption));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Aggiungi link'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Link',
            hintText: 'https://youtu.be/…',
          ),
        ),
        TextField(
          controller: _caption,
          decoration: const InputDecoration(
            labelText: 'Descrizione (facoltativa)',
            hintText: 'es. Gol di Rossi al 90°',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Aggiungi')),
    ],
  );
}
