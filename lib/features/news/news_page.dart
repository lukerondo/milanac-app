import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import '../../shared/async_view.dart';
import '../../shared/shared_links.dart';
import '../../shared/ui.dart';
import 'news_cover.dart';
import 'news_item.dart';
import 'news_repository.dart';

/// Le notizie dal mondo FC (scheda "Notizie" di Mondo Proclub), come la tavola:
/// filtri per categoria, le cose da fare prima della partita (aggiornamenti del gioco
/// e della console) e le notizie in una card, una riga ciascuna.
class NewsList extends ConsumerStatefulWidget {
  const NewsList({super.key});

  @override
  ConsumerState<NewsList> createState() => _NewsListState();
}

class _NewsListState extends ConsumerState<NewsList> {
  String _category = 'tutte';

  @override
  void initState() {
    super.initState();
    // La Home tiene le notizie in memoria: aprendo l'elenco (anche dalla notifica di un
    // aggiornamento arrivata con l'app aperta) si rileggono, mostrando intanto quelle di
    // prima.
    if (ref.exists(newsProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(newsProvider);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final news = ref.watch(newsProvider);
    final platform = ref.watch(profileProvider).value?.platform;
    final p = context.pal;

    // Tornando sulla scheda Club (Mondo resta in memoria) le notizie si rileggono.
    return OnVisible(
      onVisible: () => ref.invalidate(newsProvider),
      child: RefreshIndicator(
        // Un aggiornamento fallito lo mostra la pagina (striscia o "Riprova").
        onRefresh: () =>
            ref.refresh(newsProvider.future).then((_) {}, onError: (_) {}),
        child: AsyncView(
          value: news,
          onRetry: () => ref.invalidate(newsProvider),
          action: 'Impossibile caricare le notizie',
          data: (items) {
            final filtered = _category == 'tutte'
                ? items
                : items.where((n) => n.category == _category).toList();
            final now = DateTime.now();
            // Da fare prima della partita: l'ultimo aggiornamento del gioco e quello
            // della console (la propria, se l'ha indicata nel profilo).
            final todo = _category != 'tutte'
                ? const <NewsItem>[]
                : [
                    ?items
                        .where((n) => n.isGameUpdate && n.isRecent(now))
                        .firstOrNull,
                    ?items
                        .where(
                          (n) =>
                              n.isConsoleUpdate &&
                              n.isRecent(now) &&
                              (platform == null || n.platform == platform),
                        )
                        .firstOrNull,
                  ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in newsCategories.entries)
                      FilterPill(
                        label: c.value,
                        selected: _category == c.key,
                        onTap: () => setState(() => _category = c.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (todo.isNotEmpty) ...[
                  const SectionLabel('Da fare prima della partita'),
                  const SizedBox(height: 10),
                  for (final n in todo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: UpdateBanner(item: n),
                    ),
                  const SizedBox(height: 8),
                ],
                const SectionLabel('Notizie'),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  AppCard(
                    child: Text(
                      'Nessuna notizia in questa categoria.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: p.textMuted),
                    ),
                  )
                else
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, n) in filtered.indexed) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          NewsCard(item: n),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final _titleUpdate = RegExp(r'title update\s*[\d.]+', caseSensitive: false);
final _version = RegExp(r'\d+\.\d+[\d.\-]*');

/// Cosa da fare prima della partita: aggiornare il gioco (in evidenza, con il bordo
/// d'oro) o la console. [compact] è la versione della Home.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.item, this.compact = false});
  final NewsItem item;

  /// Versione stretta per la Home.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!item.isRecent(DateTime.now())) return const SizedBox.shrink();
    final p = context.pal;
    final console = item.isConsoleUpdate;
    final String title;
    final String subtitle;
    if (compact) {
      title = console
          ? 'Aggiornamento ${platformLabel(item.platform)} disponibile'
          : 'Nuovo aggiornamento FC 27: aggiorna il gioco prima del match!';
      subtitle = item.title;
    } else if (console) {
      final version = _version.firstMatch(item.title)?.group(0);
      title = '${platformShort(item.platform)}: aggiornamento di sistema';
      subtitle = version == null ? item.title : 'Versione $version disponibile';
    } else {
      final update = _titleUpdate.firstMatch(item.title)?.group(0);
      title = update == null
          ? 'FC 27: nuovo aggiornamento'
          : 'FC 27: ${update[0].toUpperCase()}${update.substring(1)}';
      subtitle = 'Aggiorna il gioco prima del match';
    }
    final tile = compact ? 36.0 : 40.0;
    final banner = AppCard(
      radius: 16,
      important: !console,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.all(14),
      onTap: () => openNews(item.url),
      child: Row(
        children: [
          if (console)
            Container(
              width: tile,
              height: tile,
              decoration: BoxDecoration(
                color: p.surfaceHigh,
                borderRadius: BorderRadius.circular(tile * .3),
              ),
              child: Icon(
                Icons.sports_esports_rounded,
                size: tile * .55,
                color: p.text,
              ),
            )
          else
            IconTile(Icons.download_rounded, solid: true, size: tile),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.text),
        ],
      ),
    );
    return compact
        ? Padding(padding: const EdgeInsets.only(bottom: 6), child: banner)
        : banner;
  }
}

/// Riga di una notizia: categoria, titolo, fonte e data, miniatura a destra.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final date = DateFormat('d MMM', 'it').format(item.publishedAt);
    return InkWell(
      onTap: () => openNews(item.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    newsCategoryTag(item.category).toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: p.accentText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.source} · $date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 76,
                height: 76,
                child: NewsImage(item: item, height: 76, compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openNews(String url) =>
    openExternalLink(url, mode: LaunchMode.inAppBrowserView);
