import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'news_cover.dart';
import 'news_item.dart';
import 'tonight_card.dart';
import 'news_repository.dart';

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

    return RefreshIndicator(
      onRefresh: () => ref.refresh(newsProvider.future),
      child: news.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 120),
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white38),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const TonightCard(),
              if (latestUpdate != null) _UpdateBanner(item: latestUpdate),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in newsCategories.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c.value),
                          selected: _category == c.key,
                          onSelected: (_) => setState(() => _category = c.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
    );
  }
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
        leading: const Icon(
          Icons.system_update_rounded,
          color: MilanacColors.gold,
        ),
        title: const Text(
          'Nuovo aggiornamento FC 27',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Aggiorna il gioco prima del match! · ${item.title}'),
        onTap: () => openNews(item.url),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM yyyy', 'it').format(item.publishedAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => openNews(item.url),
            child: NewsImage(item: item),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.source.toUpperCase()} · $date',
                  style: const TextStyle(
                    color: MilanacColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  item.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => openNews(item.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Leggi la notizia'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openNews(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
