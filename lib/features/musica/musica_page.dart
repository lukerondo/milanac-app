import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/shared_links.dart';
import 'soundtrack.dart';

/// Pulsante nella barra in alto: muto / riattiva la musica (o porta alla sezione).
class SoundtrackButton extends ConsumerWidget {
  const SoundtrackButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundtrackProvider);
    if (!s.hasTrack) {
      return IconButton(
        tooltip: 'Colonna sonora',
        icon: const Icon(Icons.music_note_rounded),
        onPressed: () => context.go('/musica'),
      );
    }
    return IconButton(
      tooltip: s.muted ? 'Riattiva la musica' : 'Metti in muto',
      icon: Icon(
        s.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        color: s.muted ? Colors.white54 : MilanacColors.gold,
      ),
      onPressed: () => ref.read(soundtrackProvider.notifier).toggleMute(),
    );
  }
}

class MusicaPage extends ConsumerWidget {
  const MusicaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final links = ref.watch(sharedLinksProvider(LinkCategory.musica));

    Future<void> edit([SharedLink? link]) async {
      final result = await showSharedLinkEditor(
        context,
        category: LinkCategory.musica,
        link: link,
        titleHint: 'es. FIFA 07 – colonna sonora',
      );
      if (result != null) {
        await ref.read(sharedLinksRepositoryProvider).save(result);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const _PlayerCard(),
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(Icons.queue_music_rounded, color: MilanacColors.red),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'PLAYLIST E VIDEO',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aggiungi un link',
              icon: const Icon(Icons.add_link_rounded),
              onPressed: edit,
            ),
          ],
        ),
        const Text(
          'Si aprono su YouTube o Spotify: la musica resta sulle piattaforme ufficiali.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...switch (links) {
          AsyncData(:final value) => [
            for (final l in value)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    l.url.contains('spotify')
                        ? Icons.graphic_eq_rounded
                        : Icons.play_circle_fill_rounded,
                    color: l.url.contains('spotify')
                        ? const Color(0xFF1DB954)
                        : MilanacColors.red,
                  ),
                  title: Text(l.title),
                  subtitle: l.note == null ? null : Text(l.note!),
                  trailing:
                      (me != null && (me.isDirettivo || l.createdBy == me.id))
                      ? PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') return edit(l);
                            await ref
                                .read(sharedLinksRepositoryProvider)
                                .delete(l.id);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Modifica'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Elimina'),
                            ),
                          ],
                        )
                      : const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => openSharedLink(l.url),
                ),
              ),
          ],
          AsyncError(:final error) => [Text('Errore: $error')],
          _ => [const Center(child: CircularProgressIndicator())],
        },
      ],
    );
  }
}

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(soundtrackProvider);
    final ctrl = ref.read(soundtrackProvider.notifier);

    Future<void> pick() async {
      try {
        await ctrl.pickTrack();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Impossibile usare questo file: $e')),
          );
        }
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x55C8102E), MilanacColors.surface],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.headphones_rounded, color: MilanacColors.gold),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MUSICA DI SOTTOFONDO',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!s.hasTrack) ...[
              const Text(
                'Scegli un file audio dal tuo telefono (per esempio la compilation di '
                'canzoni FIFA che hai nei Download): suonerà in sottofondo mentre usi '
                "l'app e lo metti in muto con l'altoparlante in alto.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: s.busy ? null : pick,
                icon: s.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.library_music_rounded),
                label: const Text('Scegli il file audio'),
              ),
            ] else ...[
              Text(
                s.trackName!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                s.muted ? 'In muto' : 'In riproduzione (in loop)',
                style: TextStyle(
                  color: s.muted ? Colors.white54 : MilanacColors.gold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filled(
                    tooltip: s.muted ? 'Riattiva' : 'Muto',
                    onPressed: ctrl.toggleMute,
                    icon: Icon(
                      s.muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: s.volume,
                      onChanged: s.muted ? null : ctrl.setVolume,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Parte all'apertura dell'app"),
                value: s.autoplay,
                onChanged: ctrl.setAutoplay,
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: s.busy ? null : pick,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Cambia file'),
                  ),
                  TextButton.icon(
                    onPressed: s.busy ? null : ctrl.removeTrack,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Rimuovi'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
