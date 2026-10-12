import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/shared_links.dart';
import '../carte/assign_cards_sheet.dart';
import '../carte/carte_speciali_page.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'clip_service.dart';
import 'clip_trim_page.dart';
import 'match.dart';
import 'match_editor.dart';
import 'matches_repository.dart';
import 'media_viewer.dart';
import 'risultati_page.dart';

/// Indietro: alla pagina precedente o, se la partita è stata aperta da una notifica
/// (ed è l'unica pagina), ai Risultati.
void _leave(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/risultati');

class MatchDetailPage extends ConsumerWidget {
  const MatchDetailPage({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final matches = ref.watch(matchesProvider);
    final match = matches.value?.where((m) => m.id == matchId).firstOrNull;
    final back = BackButton(onPressed: () => _leave(context));
    // Aperta da una notifica è l'unica pagina: il tasto indietro di Android porta
    // ai Risultati invece di chiudere l'app.
    final first = ModalRoute.of(context)?.isFirst ?? false;

    Widget page;
    if (match == null) {
      page = Scaffold(
        appBar: AppBar(leading: back),
        // Lo spinner finché l'elenco non è caricato; "non trovata" solo quando
        // l'elenco è arrivato e la partita non c'è (eliminata o link vecchio).
        body: matches.hasError && (!matches.isLoading || matches.retrying)
            ? ErrorRetry(
                message: friendlyError(
                  matches.error!,
                  action: 'Caricamento non riuscito',
                ),
                onRetry: () => ref.invalidate(matchesProvider),
              )
            : matches.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ErrorRetry(
                message: 'Partita non trovata.',
                onRetry: () => ref.invalidate(matchesProvider),
              ),
      );
    } else {
      page = _MatchScaffold(match: match, isDirettivo: isDirettivo, back: back);
    }
    return PopScope(
      canPop: !first,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/risultati');
      },
      child: page,
    );
  }
}

class _MatchScaffold extends ConsumerWidget {
  const _MatchScaffold({
    required this.match,
    required this.isDirettivo,
    required this.back,
  });
  final ClubMatch match;
  final bool isDirettivo;
  final Widget back;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      'Eliminare la partita e tutti i suoi media?',
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(matchesRepositoryProvider).delete(match.id);
      if (context.mounted) _leave(context);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, action: 'Eliminazione non riuscita')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(matchMediaProvider(match.id));
    return Scaffold(
      appBar: AppBar(
        leading: back,
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
              onPressed: () => _delete(context, ref),
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
          _SpecialCardsSection(match: match, isDirettivo: isDirettivo),
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
          AsyncView(
            value: media,
            onRetry: () => ref.invalidate(allMatchMediaProvider),
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

/// Le carte speciali della partita (portiere, blu automatiche, nero/oro del Direttivo).
class _SpecialCardsSection extends ConsumerWidget {
  const _SpecialCardsSection({required this.match, required this.isDirettivo});
  final ClubMatch match;
  final bool isDirettivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m,
    };
    final cards =
        (ref.watch(specialCardsProvider).value ?? const <SpecialCard>[])
            .where((c) => c.matchId == match.id)
            .toList()
          ..sort(compareCards);
    final played = match.outcome != MatchOutcome.daGiocare;
    final goalkeeper = match.goalkeeperId == null
        ? null
        : members[match.goalkeeperId]?.displayName ?? 'Ex membro';
    if (cards.isEmpty && goalkeeper == null && !isDirettivo) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.military_tech_rounded,
                  size: 18,
                  color: MilanacColors.gold,
                ),
                SizedBox(width: 8),
                Text(
                  'CARTE SPECIALI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            if (goalkeeper != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Portiere della partita: $goalkeeper',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            const SizedBox(height: 4),
            if (cards.isEmpty)
              Text(
                played
                    ? 'Nessuna carta assegnata per questa partita.'
                    : 'Le carte si assegnano dopo il risultato.',
                style: const TextStyle(color: Colors.white54),
              ),
            for (final c in cards)
              SpecialCardRow(card: c, member: members[c.playerId]),
            if (isDirettivo)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: played
                      ? () => showAssignCardsSheet(context, match)
                      : null,
                  icon: const Icon(Icons.military_tech_rounded),
                  label: Text(
                    cards.any((c) => !c.isBlue)
                        ? 'Modifica carte speciali'
                        : 'Assegna carte speciali',
                  ),
                ),
              ),
          ],
        ),
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
                if (ok != true || !context.mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(matchesRepositoryProvider).deleteMedia(media);
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        friendlyError(e, action: 'Eliminazione non riuscita'),
                      ),
                    ),
                  );
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
    await openExternalLink(media.url ?? '');
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
        // La foto scelta è una copia temporanea: si toglie anche se il caricamento fallisce.
        try {
          messenger.showSnackBar(
            const SnackBar(content: Text('Caricamento foto…')),
          );
          await repo.uploadMedia(
            matchId,
            type: MediaType.photo,
            bytes: await file.readAsBytes(),
            extension: 'jpg',
          );
        } finally {
          await ClipService.discard(file.path);
        }
      case 'video' || 'camera':
        final file = await ImagePicker().pickVideo(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxDuration: const Duration(seconds: maxClipSeconds),
        );
        if (file == null) return;
        // Il video scelto (o registrato) è una copia temporanea che può pesare
        // centinaia di MB: si toglie sempre, anche se si annulla o il caricamento fallisce.
        try {
          if (!context.mounted) return;
          final clip = await Navigator.of(context, rootNavigator: true)
              .push<PreparedClip>(
                MaterialPageRoute(
                  builder: (_) => ClipTrimPage(path: file.path),
                ),
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
        } finally {
          await ClipService.discard(file.path);
        }
    }
    messenger.showSnackBar(const SnackBar(content: Text('Contenuto aggiunto')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyError(e, action: 'Caricamento non riuscito')),
      ),
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
