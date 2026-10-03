import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'news_cover.dart';
import 'news_item.dart';
import 'news_repository.dart';
import 'tonight_panel.dart';

class NewsPage extends ConsumerStatefulWidget {
  const NewsPage({super.key});

  @override
  ConsumerState<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends ConsumerState<NewsPage> {
  String _category = 'tutte';

  @override
  Widget build(BuildContext context) {
    final news = ref.watch(newsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Bottone tondo in basso a destra: apre il pannello della serata.
      floatingActionButton: const TonightFab(),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(newsProvider.future),
        child: news.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const _NewsHeader(),
              const SizedBox(height: 80),
              const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.white38,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Impossibile caricare le notizie.\n$e',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          data: (items) {
            final filtered = _category == 'tutte'
                ? items
                : items.where((n) => n.category == _category).toList();
            final latestUpdate = items.where((n) => n.isGameUpdate).firstOrNull;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                const _NewsHeader(),
                if (latestUpdate != null) _UpdateBanner(item: latestUpdate),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in newsCategories.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c.value),
                            selected: _category == c.key,
                            onSelected: (_) =>
                                setState(() => _category = c.key),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(
                      child: Text('Nessuna notizia in questa categoria.'),
                    ),
                  ),
                for (final n in filtered) NewsCard(item: n),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Titolo della Home.
class _NewsHeader extends StatelessWidget {
  const _NewsHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 46,
          decoration: BoxDecoration(
            color: MilanacColors.red,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notizie dal mondo FC',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Text(
                'Aggiornamenti, tornei, Ultimate Team e Pro Clubs',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final isRecent = DateTime.now().difference(item.publishedAt).inDays <= 3;
    if (!isRecent) return const SizedBox.shrink();
    return Card(
      color: MilanacColors.redDark,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        dense: true,
        leading: const Icon(
          Icons.system_update_rounded,
          color: MilanacColors.gold,
        ),
        title: const Text(
          'Nuovo aggiornamento: aggiorna il gioco prima del match!',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openNews(item.url),
      ),
    );
  }
}

/// Card stretta e rettangolare: miniatura a sinistra, testo a destra.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM', 'it').format(item.publishedAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openNews(item.url),
        child: SizedBox(
          height: 112,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 104,
                child: NewsImage(item: item, height: 112, compact: true),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.source.toUpperCase()} · $date',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MilanacColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Text(
                          item.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              'Leggi la notizia',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MilanacColors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: MilanacColors.red,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openNews(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
