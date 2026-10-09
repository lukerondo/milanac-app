import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/shared_links.dart';
import '../news/news_page.dart';
import '../risultati/match.dart' show youtubeId;
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

const _anyRole = 'Tutti i ruoli';

/// Mondo Proclub: i video dei creator (pubblicati dal Direttivo, proposti dai
/// giocatori) e le notizie dal mondo FC.
class MondoPage extends ConsumerStatefulWidget {
  const MondoPage({super.key, this.initialTab});

  /// "video" (predefinita) oppure "notizie".
  final String? initialTab;

  @override
  ConsumerState<MondoPage> createState() => _MondoPageState();
}

class _MondoPageState extends ConsumerState<MondoPage>
    with SingleTickerProviderStateMixin {
  late final _tabs =
      TabController(
          length: 2,
          vsync: this,
          initialIndex: widget.initialTab == 'notizie' ? 1 : 0,
        )
        ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              heroTag: 'video',
              backgroundColor: MilanacColors.red,
              onPressed: () => proposeVideo(context, ref),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(isDirettivo ? 'Aggiungi video' : 'Proponi un video'),
            )
          : null,
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            indicatorColor: MilanacColors.red,
            labelColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.smart_display_rounded), text: 'Video'),
              Tab(icon: Icon(Icons.newspaper_rounded), text: 'Notizie'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [_VideoTab(), NewsList()],
            ),
          ),
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
    messenger.showSnackBar(SnackBar(content: Text('Non salvato: $e')));
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
    return links.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (all) {
        final published =
            all.where((l) => l.isPublished).toList()..sort(
              (a, b) => (b.publishedAt ?? b.createdAt ?? DateTime(2000))
                  .compareTo(a.publishedAt ?? a.createdAt ?? DateTime(2000)),
            );
        final proposals = all
            .where(
              (l) =>
                  !l.isPublished && (isDirettivo || l.createdBy == me?.id),
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
              _Header(
                isDirettivo
                    ? 'Proposte da approvare (${proposals.length})'
                    : 'Le tue proposte',
              ),
              for (final l in proposals)
                _ProposalCard(
                  link: l,
                  proposer: names[l.createdBy] ?? 'Un giocatore',
                  canDecide: isDirettivo,
                ),
            ],
            const _Header('Video dei creator'),
            const Text(
              'Scelti dal Direttivo: build, tattiche e consigli per ogni ruolo. '
              'Hai visto un video utile? Proponilo.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 8),
            if (roles.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Tutti'),
                    selected: _role == null,
                    onSelected: (_) => setState(() => _role = null),
                  ),
                  for (final r in fieldPositions.where(roles.contains))
                    ChoiceChip(
                      label: Text(r),
                      selected: _role == r,
                      onSelected: (_) => setState(() => _role = r),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    'Nessun video ancora.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            for (final l in shown) VideoCard(link: l, canEdit: isDirettivo),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontFamily: sportFont,
        fontSize: 15,
        letterSpacing: 1.5,
        color: MilanacColors.gold,
      ),
    ),
  );
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
    final placeholder = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [MilanacColors.redDark, MilanacColors.black],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
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
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 30,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Video pubblicato: miniatura, titolo, creator, ruolo e data.
class VideoCard extends ConsumerWidget {
  const VideoCard({super.key, required this.link, this.canEdit = false});
  final SharedLink link;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = link.publishedAt ?? link.createdAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openSharedLink(link.url),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              VideoThumb(url: link.url),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (link.tag != null) link.tag!,
                        if (link.note != null && link.note!.isNotEmpty)
                          link.note!,
                        if (date != null) DateFormat('d MMM', 'it').format(date),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      await ref.read(sharedLinksRepositoryProvider).delete(
                        link.id,
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
    final repo = ref.read(sharedLinksRepositoryProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: MilanacColors.gold.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
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
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          [
                            'Proposto da $proposer',
                            if (link.tag != null) link.tag!,
                          ].join(' · '),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: canDecide
                  ? [
                      TextButton.icon(
                        onPressed: () => repo.delete(link.id),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Scarta'),
                      ),
                      FilledButton.icon(
                        onPressed: () => repo.save(
                          link.copyWith(status: LinkStatus.pubblicato),
                        ),
                        icon: const Icon(Icons.publish_rounded),
                        label: const Text('Pubblica'),
                      ),
                    ]
                  : [
                      const Chip(
                        avatar: Icon(Icons.hourglass_top_rounded, size: 16),
                        label: Text('In attesa del Direttivo'),
                      ),
                      TextButton(
                        onPressed: () => repo.delete(link.id),
                        child: const Text('Ritira'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
