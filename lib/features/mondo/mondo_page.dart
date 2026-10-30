import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import '../news/news_page.dart';
import '../risultati/match.dart' show youtubeId;
import '../risultati/result_ui.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

const _anyRole = 'Tutti i ruoli';

/// Mondo Proclub: le notizie dal mondo FC e i video dei creator (pubblicati dal
/// Direttivo, proposti dai giocatori), come la tavola.
///
/// La scheda scelta sta nella rotta (`/mondo?scheda=notizie`), come in Partite: anche
/// le schede in alto cambiano la rotta, così una notifica la segue sempre, anche se
/// arriva una seconda volta con la stessa `?scheda=`.
class MondoPage extends ConsumerWidget {
  const MondoPage({super.key, this.tab});

  /// "video" (predefinita) oppure "notizie".
  final String? tab;

  /// Le schede nell'ordine della tavola.
  static const tabs = ['notizie', 'video'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    // 0 = Notizie, 1 = Video; senza scheda, i video.
    final selected = tab == 'notizie' ? 0 : 1;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: selected == 1
          ? FloatingActionButton.extended(
              heroTag: 'video',
              onPressed: () => proposeVideo(context, ref),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(isDirettivo ? 'Aggiungi video' : 'Proponi un video'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedTabs(
              labels: const ['Notizie', 'Video'],
              selected: selected,
              onSelected: (i) {
                if (i != selected) context.go('/mondo?scheda=${tabs[i]}');
              },
            ),
          ),
          // Solo la scheda scelta resta costruita (e collegata al server).
          Expanded(child: selected == 0 ? const NewsList() : const _VideoTab()),
        ],
      ),
    );
  }
}

/// Finestra per proporre (giocatori) o aggiungere (Direttivo) un video.
Future<void> proposeVideo(
  BuildContext context,
  WidgetRef ref, {
  SharedLink? link,
}) async {
  final isDirettivo = ref.read(profileProvider).value?.isDirettivo ?? false;
  final messenger = ScaffoldMessenger.of(context);
  final edited = await showSharedLinkEditor(
    context,
    category: LinkCategory.video,
    link: link?.copyWith(tag: link.tag ?? _anyRole),
    tags: [_anyRole, ...fieldPositions],
    title: link != null
        ? 'Modifica video'
        : isDirettivo
        ? 'Nuovo video'
        : 'Proponi un video',
    titleHint: 'es. La build da ATT più forte',
    noteLabel: 'Creator (facoltativo)',
  );
  if (edited == null) return;
  final tag = edited.tag == _anyRole ? null : edited.tag;
  final toSave = link == null
      ? SharedLink(
          id: '',
          category: LinkCategory.video,
          title: edited.title,
          url: edited.url,
          note: edited.note,
          tag: tag,
          status: isDirettivo ? LinkStatus.pubblicato : LinkStatus.proposto,
        )
      : SharedLink(
          id: link.id,
          category: link.category,
          title: edited.title,
          url: edited.url,
          note: edited.note,
          tag: tag,
          createdBy: link.createdBy,
          createdAt: link.createdAt,
          sortOrder: link.sortOrder,
          status: link.status,
          publishedBy: link.publishedBy,
          publishedAt: link.publishedAt,
        );
  try {
    await ref.read(sharedLinksRepositoryProvider).save(toSave);
    if (link == null && !isDirettivo) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Proposta inviata: il Direttivo la pubblicherà.'),
        ),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e, action: 'Non salvato'))),
    );
  }
}

/// Esegue un'azione su un video (pubblica, scarta, elimina…) e, se non riesce,
/// lo dice con un messaggio invece di lasciare un'eccezione non gestita.
Future<void> _act(
  BuildContext context,
  Future<void> Function() action, {
  required String failure,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e, action: failure))),
    );
  }
}

class _VideoTab extends ConsumerStatefulWidget {
  const _VideoTab();

  @override
  ConsumerState<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends ConsumerState<_VideoTab> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider).value;
    final isDirettivo = me?.isDirettivo ?? false;
    final links = ref.watch(sharedLinksProvider(LinkCategory.video));
    final names = {
      for (final m in ref.watch(rosaProvider).value ?? const <Member>[])
        m.id: m.displayName,
    };
    final p = context.pal;
    return AsyncView(
      value: links,
      onRetry: () => ref.invalidate(sharedLinksProvider(LinkCategory.video)),
      data: (all) {
        final published = all.where((l) => l.isPublished).toList()
          ..sort(
            (a, b) => (b.publishedAt ?? b.createdAt ?? DateTime(2000))
                .compareTo(a.publishedAt ?? a.createdAt ?? DateTime(2000)),
          );
        final proposals = all
            .where(
              (l) => !l.isPublished && (isDirettivo || l.createdBy == me?.id),
            )
            .toList();
        final roles = {for (final l in published) ?l.tag};
        final shown = published
            .where((l) => _role == null || l.tag == _role)
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (proposals.isNotEmpty) ...[
              SectionLabel(
                isDirettivo
                    ? 'Proposte da approvare (${proposals.length})'
                    : 'Le tue proposte',
                gold: true,
              ),
              const SizedBox(height: 10),
              for (final l in proposals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ProposalCard(
                    link: l,
                    proposer: names[l.createdBy] ?? 'Un giocatore',
                    canDecide: isDirettivo,
                  ),
                ),
              const SizedBox(height: 8),
            ],
            const SectionLabel('Video dei creator'),
            const SizedBox(height: 6),
            Text(
              'Scelti dal Direttivo: build, tattiche e consigli per ogni ruolo. '
              'Hai visto un video utile? Proponilo.',
              style: TextStyle(fontSize: 15, color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            if (roles.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterPill(
                    label: 'Tutti',
                    square: true,
                    selected: _role == null,
                    onTap: () => setState(() => _role = null),
                  ),
                  for (final r in fieldPositions.where(roles.contains))
                    FilterPill(
                      label: r,
                      square: true,
                      selected: _role == r,
                      onTap: () => setState(() => _role = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (shown.isEmpty)
              AppCard(
                child: Text(
                  'Nessun video ancora.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: p.textMuted),
                ),
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, l) in shown.indexed) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      VideoCard(link: l, canEdit: isDirettivo),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Anteprima di un video: miniatura di YouTube se il link è di YouTube.
class VideoThumb extends StatelessWidget {
  const VideoThumb({
    super.key,
    required this.url,
    this.width = 120,
    this.height = 68,
  });
  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final id = youtubeId(url);
    final placeholder = ColoredBox(color: context.pal.surfaceHigher);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (id == null)
              placeholder
            else
              Image.network(
                'https://img.youtube.com/vi/$id/mqdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
            // Sopra la miniatura: tondo scuro con il triangolo, come i lettori video.
            Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MilanacColors.black.withValues(alpha: .6),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: MilanacColors.ivory,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Video pubblicato: miniatura, titolo, ruolo, creator e data (riga di una card).
class VideoCard extends ConsumerWidget {
  const VideoCard({super.key, required this.link, this.canEdit = false});
  final SharedLink link;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final date = link.publishedAt ?? link.createdAt;
    return InkWell(
      onTap: () => openSharedLink(link.url),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, canEdit ? 4 : 16, 12),
        child: Row(
          children: [
            VideoThumb(url: link.url, width: 96, height: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (link.tag != null) link.tag!,
                      if (link.note != null && link.note!.isNotEmpty)
                        link.note!,
                      if (date != null) DateFormat('d MMM', 'it').format(date),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textMuted),
                  ),
                ],
              ),
            ),
            if (canEdit)
              PopupMenuButton<String>(
                tooltip: 'Altre azioni',
                onSelected: (v) async {
                  if (v == 'delete') {
                    await _act(
                      context,
                      () => ref
                          .read(sharedLinksRepositoryProvider)
                          .delete(link.id),
                      failure: 'Eliminazione non riuscita',
                    );
                  } else if (context.mounted) {
                    await proposeVideo(context, ref, link: link);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifica')),
                  PopupMenuItem(value: 'delete', child: Text('Elimina')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Video proposto da un giocatore: il Direttivo lo pubblica o lo scarta.
class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({
    required this.link,
    required this.proposer,
    required this.canDecide,
  });
  final SharedLink link;
  final String proposer;
  final bool canDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final repo = ref.read(sharedLinksRepositoryProvider);
    return AppCard(
      important: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openSharedLink(link.url),
            child: Row(
              children: [
                VideoThumb(url: link.url, width: 96, height: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      Text(
                        [
                          'Proposto da $proposer',
                          if (link.tag != null) link.tag!,
                        ].join(' · '),
                        style: TextStyle(fontSize: 14, color: p.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: canDecide
                  ? [
                      TextButton(
                        onPressed: () => _act(
                          context,
                          () => repo.delete(link.id),
                          failure: 'Non scartato',
                        ),
                        child: const Text('Scarta'),
                      ),
                      // Oro tenue: l'oro pieno resta per l'azione della pagina.
                      FilledButton.tonal(
                        onPressed: () => _act(
                          context,
                          () => repo.save(
                            link.copyWith(status: LinkStatus.pubblicato),
                          ),
                          failure: 'Pubblicazione non riuscita',
                        ),
                        child: const Text('Pubblica'),
                      ),
                    ]
                  : [
                      StatusPill(
                        'In attesa del Direttivo',
                        color: p.warning,
                        background: p.warningBg,
                      ),
                      TextButton(
                        onPressed: () => _act(
                          context,
                          () => repo.delete(link.id),
                          failure: 'Proposta non ritirata',
                        ),
                        child: const Text('Ritira'),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}
