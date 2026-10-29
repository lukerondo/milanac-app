import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/gold_loader.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import 'soundtrack.dart';

/// Pulsante nella barra in alto (sempre scura): muto / riattiva la musica, in oro
/// quando suona e avorio spento in muto (o porta alla sezione se non c'è musica).
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
        color: s.muted ? MilanacColors.ivoryMuted : MilanacColors.goldLight,
      ),
      onPressed: () => ref.read(soundtrackProvider.notifier).toggleMute(),
    );
  }
}

/// Colonna sonora: il brano scelto dal telefono con i comandi, come la tavola, e
/// sotto le playlist e i video del club.
class MusicaPage extends ConsumerWidget {
  const MusicaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final links = ref.watch(sharedLinksProvider(LinkCategory.musica));
    final s = ref.watch(soundtrackProvider);
    final ctrl = ref.read(soundtrackProvider.notifier);
    final p = context.pal;

    final messenger = ScaffoldMessenger.of(context);
    void failed(Object e, String action) => messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e, action: action))),
    );

    Future<void> pick() async {
      try {
        await ctrl.pickTrack();
      } catch (e) {
        failed(e, 'Impossibile usare questo file (prova con un mp3 o un m4a)');
      }
    }

    Future<void> edit([SharedLink? link]) async {
      final result = await showSharedLinkEditor(
        context,
        category: LinkCategory.musica,
        link: link,
        titleHint: 'es. FIFA 07 – colonna sonora',
      );
      if (result == null) return;
      try {
        await ref.read(sharedLinksRepositoryProvider).save(result);
      } catch (e) {
        failed(e, 'Non salvato');
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _PlayerCard(onPick: pick),
        if (s.hasTrack) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: s.busy ? null : pick,
            child: const Text('Scegli un altro file'),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: p.danger),
            onPressed: s.busy ? null : ctrl.removeTrack,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Rimuovi la musica'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          "La musica suona in sottofondo mentre usi l'app. Il pulsante per il "
          'muto resta sempre in alto. Nessuna canzone è inclusa nell\'app.',
          style: TextStyle(fontSize: 15, height: 1.5, color: p.textSecondary),
        ),
        const SizedBox(height: 24),
        SectionLabel(
          'Playlist e video',
          trailing: IconButton(
            tooltip: 'Aggiungi un link',
            icon: Icon(Icons.add_link_rounded, color: p.accentText),
            onPressed: edit,
          ),
        ),
        Text(
          'Si aprono su YouTube o Spotify: la musica resta sulle piattaforme '
          'ufficiali.',
          style: TextStyle(fontSize: 14, color: p.textMuted),
        ),
        const SizedBox(height: 10),
        AsyncView(
          value: links,
          onRetry: () =>
              ref.invalidate(sharedLinksProvider(LinkCategory.musica)),
          data: (value) => value.isEmpty
              ? const SizedBox.shrink()
              : AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, l) in value.indexed) ...[
                        if (i > 0) const Divider(indent: 68, endIndent: 16),
                        _LinkRow(
                          link: l,
                          canEdit:
                              me != null &&
                              (me.isDirettivo || l.createdBy == me.id),
                          onEdit: () => edit(l),
                          onDelete: () async {
                            try {
                              await ref
                                  .read(sharedLinksRepositoryProvider)
                                  .delete(l.id);
                            } catch (e) {
                              failed(e, 'Eliminazione non riuscita');
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.link,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });
  final SharedLink link;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final spotify = link.url.contains('spotify');
    return InkWell(
      onTap: () => openSharedLink(link.url),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, canEdit ? 4 : 16, 12),
        child: Row(
          children: [
            IconTile(
              spotify ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (link.note != null)
                    Text(
                      link.note!,
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                ],
              ),
            ),
            if (canEdit)
              PopupMenuButton<String>(
                tooltip: 'Altre azioni',
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifica')),
                  PopupMenuItem(value: 'delete', child: Text('Elimina')),
                ],
              )
            else
              Icon(Icons.open_in_new_rounded, size: 20, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Il brano in riproduzione: copertina, nome, avanzamento e comandi (avvio
/// automatico, pausa, volume). Card in evidenza, sempre scura.
class _PlayerCard extends ConsumerStatefulWidget {
  const _PlayerCard({required this.onPick});
  final Future<void> Function() onPick;

  @override
  ConsumerState<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends ConsumerState<_PlayerCard> {
  /// Aggiorna la barra di avanzamento mentre suona (solo se la durata è nota).
  Timer? _tick;

  void _ticking(bool on) {
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _volume() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final s = ref.watch(soundtrackProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Volume', style: Theme.of(context).textTheme.titleLarge),
                Row(
                  children: [
                    const Icon(Icons.volume_mute_rounded),
                    Expanded(
                      child: Slider(
                        value: s.volume,
                        onChanged: ref
                            .read(soundtrackProvider.notifier)
                            .setVolume,
                      ),
                    ),
                    const Icon(Icons.volume_up_rounded),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(soundtrackProvider);
    final ctrl = ref.read(soundtrackProvider.notifier);
    final engine = ref.read(soundtrackEngineProvider);
    final total = engine.duration;
    final known = s.hasTrack && total != null && total.inMilliseconds > 0;
    _ticking(known && s.playing);
    final progress = known
        ? (engine.position.inMilliseconds % total.inMilliseconds) /
              total.inMilliseconds
        : 0.0;
    // La card è sempre scura: comandi con la tavolozza scura anche nel tema chiaro.
    const dark = AppPalette.dark;

    return AppCard(
      hero: true,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Column(
        children: [
          const _Artwork(),
          const SizedBox(height: 16),
          if (!s.hasTrack) ...[
            const Text(
              'Nessuna musica scelta',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HeroText.primary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Scegli un file audio dal tuo telefono (per esempio la compilation '
              'di canzoni FIFA che hai nei Download): suonerà in sottofondo '
              "mentre usi l'app.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: HeroText.secondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: MilanacColors.gold,
                foregroundColor: MilanacColors.ink,
              ),
              onPressed: s.busy ? null : widget.onPick,
              icon: s.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: GoldLoader(size: 16),
                    )
                  : const Icon(Icons.library_music_rounded),
              label: const Text('Scegli il file audio'),
            ),
          ] else ...[
            Text(
              s.trackName!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HeroText.primary,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Scelto dal tuo telefono',
              style: TextStyle(fontSize: 14, color: HeroText.secondary),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                color: MilanacColors.goldLight,
                backgroundColor: dark.borderStrong,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundButton(
                  tooltip: s.autoplay
                      ? "Parte all'apertura dell'app: sì"
                      : "Parte all'apertura dell'app: no",
                  icon: Icons.autorenew_rounded,
                  selected: s.autoplay,
                  onPressed: () => ctrl.setAutoplay(!s.autoplay),
                ),
                const SizedBox(width: 22),
                Tooltip(
                  message: s.muted ? 'Fai partire la musica' : 'Metti in pausa',
                  child: Material(
                    color: MilanacColors.gold,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: ctrl.toggleMute,
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Icon(
                          s.muted
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 34,
                          color: MilanacColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 22),
                _RoundButton(
                  tooltip: 'Volume',
                  icon: s.volume == 0
                      ? Icons.volume_mute_rounded
                      : Icons.volume_up_rounded,
                  onPressed: _volume,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Pulsante tondo dei comandi: [selected] = interruttore acceso (oro tenue).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    const dark = AppPalette.dark;
    final on = selected ?? false;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: selected,
        child: Material(
          color: on ? dark.accentTint : dark.surfaceHigher,
          shape: CircleBorder(
            side: on
                ? BorderSide(color: dark.accentTintBorder)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                icon,
                size: 22,
                color: on ? MilanacColors.goldLight : MilanacColors.ivory,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copertina: righe d'oro su nero con la nota al centro (oggetto fisso, sempre scuro).
class _Artwork extends StatelessWidget {
  const _Artwork();

  @override
  Widget build(BuildContext context) => Container(
    width: 120,
    height: 120,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppPalette.dark.chipBorder),
    ),
    child: CustomPaint(
      painter: const _StripesPainter(),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MilanacColors.gold,
          ),
          child: const Icon(
            Icons.music_note_rounded,
            size: 30,
            color: MilanacColors.ink,
          ),
        ),
      ),
    ),
  );
}

class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = MilanacColors.ink);
    final line = Paint()
      ..color = MilanacColors.gold.withValues(alpha: .32)
      ..strokeWidth = 1.5;
    for (var x = .75; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant _StripesPainter old) => false;
}
