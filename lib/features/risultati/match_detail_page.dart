import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/gold_loader.dart';
import '../../shared/member_photo.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import '../carta/card_colors.dart';
import '../carta/card_stats.dart';
import '../carte/assign_cards_sheet.dart';
import '../carte/carte_speciali_page.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';
import 'clip_service.dart';
import 'clip_trim_page.dart';
import 'match.dart';
import 'match_editor.dart';
import 'match_tv.dart';
import 'matches_repository.dart';
import 'media_viewer.dart';
import 'result_poster.dart';
import 'result_ui.dart';

/// Indietro: alla pagina precedente o, se la partita è stata aperta da una notifica
/// (ed è l'unica pagina), ai Risultati.
void _leave(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/risultati');

/// Barra in alto della partita: scura come la testata del risultato, con il filo d'oro.
PreferredSizeWidget _bar(
  BuildContext context, {
  required Widget back,
  List<Widget> actions = const [],
}) => AppBar(
  backgroundColor: context.pal.hero,
  leading: back,
  title: const Text('PARTITA'),
  actions: actions,
  flexibleSpace: const Align(alignment: Alignment.topCenter, child: GoldRule()),
);

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
        appBar: _bar(context, back: back),
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
            ? const Center(child: GoldLoader())
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
      'Eliminare la partita con i suoi media e le carte speciali che ha '
      'assegnato?',
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
    return Scaffold(
      appBar: _bar(
        context,
        back: back,
        actions: [
          IconButton(
            tooltip: 'Condividi',
            icon: const Icon(Icons.ios_share_rounded),
            // La grafica del risultato (o il testo), con l'anteprima.
            onPressed: () => openResultPoster(context, match),
          ),
          if (isDirettivo)
            PopupMenuButton<String>(
              tooltip: 'Altre azioni',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) => v == 'edit'
                  ? showMatchEditor(context, match: match)
                  : _delete(context, ref),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Modifica partita')),
                PopupMenuItem(value: 'delete', child: Text('Elimina partita')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          TvScoreHeader(match: match),
          const GoldFadeLine(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (match.timeline.isEmpty)
                  _ScorersCard(match: match)
                else
                  MatchTimelineCard(match: match),
                _SpecialCardsCard(match: match, isDirettivo: isDirettivo),
                _MediaSection(match: match, isDirettivo: isDirettivo),
                if (isDirettivo) _DirettivoActions(match: match),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marcatori (con foto e gol) e la nota della partita.
class _ScorersCard extends ConsumerWidget {
  const _ScorersCard({required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final played = match.outcome != MatchOutcome.daGiocare;
    // I nomi si riconoscono tra i giocatori della squadra, come per i gol della carta.
    final players = [
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        if (m.active &&
            m.role != ClubRole.pending &&
            m.teams.contains(match.team))
          m,
    ];
    final lines = played
        ? scorerLines(match.scorers, players)
        : const <(String, int, Member?)>[];
    final note = match.notes?.trim() ?? '';
    if (lines.isEmpty && note.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lines.isNotEmpty) ...[
              const SectionLabel('Marcatori'),
              for (final (name, goals, member) in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      if (member != null)
                        MemberAvatar(member: member, radius: 17)
                      else
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: p.surfaceHigher,
                          child: Text(
                            initialsOf(name),
                            style: TextStyle(
                              fontFamily: sportFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '$goals gol',
                        style: const TextStyle(
                          fontFamily: sportFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (note.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: lines.isEmpty ? 0 : 12),
                child: Text(
                  '«$note»',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: p.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le carte speciali della giornata (portiere, blu automatiche, nero/oro del
/// Direttivo): card in evidenza che porta alle Carte speciali.
class _SpecialCardsCard extends ConsumerWidget {
  const _SpecialCardsCard({required this.match, required this.isDirettivo});
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
          ..sort(compareCardsForDisplay);
    final goalkeeper = match.goalkeeperId == null
        ? null
        : members[match.goalkeeperId]?.displayName ?? 'Ex membro';
    final played = match.outcome != MatchOutcome.daGiocare;
    if (cards.isEmpty && goalkeeper == null && !(isDirettivo && played)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        hero: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        onTap: () => openSpecialCards(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'CARTE SPECIALI DELLA GIORNATA',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: HeroText.accent,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: HeroText.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (cards.isEmpty)
              const Text(
                'Nessuna carta assegnata per questa partita.',
                style: TextStyle(fontSize: 15, color: HeroText.secondary),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final cell = (box.maxWidth - 3 * 8) / 4;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      for (final c in cards)
                        SizedBox(
                          width: cell,
                          child: _CardWinner(
                            card: c,
                            member: members[c.playerId],
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (goalkeeper != null) ...[
              const SizedBox(height: 12),
              Text(
                'Portiere della partita: $goalkeeper',
                style: const TextStyle(fontSize: 14, color: HeroText.secondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Premiato della giornata: foto con l'anello del colore della carta, nome, reparto e bonus.
class _CardWinner extends StatelessWidget {
  const _CardWinner({required this.card, required this.member});
  final SpecialCard card;
  final Member? member;

  @override
  Widget build(BuildContext context) {
    final ring = card.isBlue ? CardColors.blueRing : MilanacColors.gold;
    final text = card.isBlue ? CardColors.blueText : HeroText.accent;
    final m = member;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
          child: m == null
              ? const CircleAvatar(
                  radius: 20,
                  backgroundColor: CardColors.portrait,
                  child: Icon(
                    Icons.person_rounded,
                    size: 22,
                    color: HeroText.secondary,
                  ),
                )
              : MemberAvatar(
                  member: m,
                  radius: 20,
                  background: CardColors.portrait,
                  foreground: HeroText.primary,
                ),
        ),
        const SizedBox(height: 4),
        Text(
          m == null ? 'Ex membro' : shortName(m.displayName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: HeroText.primary,
          ),
        ),
        Text(
          '${card.reparto} +${card.bonus}',
          maxLines: 1,
          style: TextStyle(fontSize: 12, color: text),
        ),
      ],
    );
  }
}

/// Gol e highlights: foto, clip e video di YouTube in grande, da scorrere di lato (foto
/// e clip si aprono a tutto schermo, una dopo l'altra); gli altri link in riga sotto.
class _MediaSection extends ConsumerWidget {
  const _MediaSection({required this.match, required this.isDirettivo});
  final ClubMatch match;
  final bool isDirettivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(matchMediaProvider(match.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 10),
          child: SectionLabel('Gol e highlights'),
        ),
        AsyncView(
          value: media,
          onRetry: () => ref.invalidate(allMatchMediaProvider),
          loading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: GoldBar(),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Nessun video o foto per questa partita.',
                  style: TextStyle(fontSize: 15, color: context.pal.textMuted),
                ),
              );
            }
            final big = [
              for (final m in items)
                if (m.type != MediaType.link || youtubeId(m.url ?? '') != null)
                  m,
            ];
            final gallery = [
              for (final m in big)
                if (m.type != MediaType.link) m,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (big.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // Con più contenuti si intravede il successivo.
                        final width = big.length == 1
                            ? box.maxWidth
                            : box.maxWidth * .84;
                        return SizedBox(
                          height: width * 9 / 16,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: big.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, i) => SizedBox(
                              width: width,
                              child: _MediaTile(
                                media: big[i],
                                canDelete: isDirettivo,
                                onOpen: () => openMedia(
                                  context,
                                  big[i],
                                  gallery: gallery,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                for (final m in items)
                  if (!big.contains(m))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MediaRow(media: m, canDelete: isDirettivo),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Il Direttivo toglie un contenuto (tenendolo premuto), dopo la conferma.
Future<void> _deleteMedia(
  BuildContext context,
  WidgetRef ref,
  MatchMedia media,
) async {
  final ok = await _confirm(context, 'Eliminare questo contenuto?');
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(matchesRepositoryProvider).deleteMedia(media);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyError(e, action: 'Eliminazione non riuscita')),
      ),
    );
  }
}

/// Foto, clip o video di YouTube in grande, come un replay in TV: l'immagine (o
/// l'anteprima di YouTube), il tasto play e, nel sottopancia, il tipo e la didascalia.
class _MediaTile extends ConsumerWidget {
  const _MediaTile({
    required this.media,
    required this.canDelete,
    required this.onOpen,
  });
  final MatchMedia media;
  final bool canDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = media.type == MediaType.link ? youtubeId(media.url ?? '') : null;
    const blank = ColoredBox(color: MilanacColors.surfaceHigh);
    final picture = switch (media.type) {
      MediaType.photo => MediaImage(media: media, fit: BoxFit.cover),
      MediaType.video => blank,
      MediaType.link => Image.network(
        'https://img.youtube.com/vi/$id/mqdefault.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => blank,
      ),
    };
    final (tag, title) = switch (media.type) {
      MediaType.photo => ('FOTO', media.caption ?? 'Foto'),
      MediaType.video => (
        media.durationS == null ? 'CLIP' : 'CLIP · ${media.durationS}"',
        media.caption ?? 'Clip',
      ),
      MediaType.link => ('YOUTUBE', media.caption ?? 'Video'),
    };
    return Material(
      color: MilanacColors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onOpen,
        onLongPress: canDelete ? () => _deleteMedia(context, ref, media) : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                  stops: [.45, 1],
                ),
              ),
            ),
            if (media.type != MediaType.photo)
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MilanacColors.black.withValues(alpha: .55),
                    border: Border.all(
                      color: MilanacColors.goldLight,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 34,
                    color: MilanacColors.ivory,
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MilanacColors.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontFamily: sportFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: MilanacColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: MilanacColors.ivory,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le azioni del Direttivo in fondo: carte della giornata e nuovi contenuti.
class _DirettivoActions extends ConsumerWidget {
  const _DirettivoActions({required this.match});
  final ClubMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final played = match.outcome != MatchOutcome.daGiocare;
    final hasNeroOro =
        (ref.watch(specialCardsProvider).value ?? const <SpecialCard>[]).any(
          (c) => c.matchId == match.id && !c.isBlue,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: played ? () => showAssignCardsSheet(context, match) : null,
          child: Text(
            hasNeroOro
                ? 'Modifica carte della giornata'
                : 'Assegna carte della giornata',
          ),
        ),
        if (!played)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Le carte si assegnano dopo il risultato.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.pal.textMuted),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _addMedia(context, ref, match.id),
          icon: const Icon(Icons.add_photo_alternate_rounded),
          label: const Text('Aggiungi video o foto'),
        ),
      ],
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

/// Riga di un link (non di YouTube): icona, titolo, sito e freccia. Il Direttivo lo
/// toglie tenendolo premuto.
class _MediaRow extends ConsumerWidget {
  const _MediaRow({required this.media, required this.canDelete});
  final MatchMedia media;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final url = media.url ?? '';
    final radius = BorderRadius.circular(18);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openMedia(context, media),
        onLongPress: canDelete ? () => _deleteMedia(context, ref, media) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 40,
                  height: 40,
                  color: p.surfaceHigh,
                  child: Icon(
                    Icons.link_rounded,
                    size: 24,
                    color: p.accentText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.caption ?? 'Video',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      Uri.tryParse(url)?.host.replaceFirst('www.', '') ??
                          'Link',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded, size: 20, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Apre un contenuto: i link fuori dall'app, foto e clip a tutto schermo (con le altre
/// di [gallery] da scorrere di lato).
Future<void> openMedia(
  BuildContext context,
  MatchMedia media, {
  List<MatchMedia> gallery = const [],
}) async {
  if (media.type == MediaType.link) {
    await openExternalLink(media.url ?? '');
    return;
  }
  final items = gallery.contains(media) ? gallery : [media];
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => MediaGallery(items: items, initial: items.indexOf(media)),
    ),
  );
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
        const SizedBox(height: 12),
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
