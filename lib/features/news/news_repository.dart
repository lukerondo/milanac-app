import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import 'news_item.dart';

/// Ultime notizie (raccolte ogni 3 ore dal job GitHub Actions nella tabella `news`).
final newsProvider = FutureProvider<List<NewsItem>>((ref) async {
  if (AppConfig.isDemo) return _demoNews;
  final rows = await ref
      .watch(supabaseProvider)
      .from('news')
      .select()
      .order('published_at', ascending: false)
      .limit(100);
  return rows.map(NewsItem.fromMap).toList();
});

final _demoNews = <NewsItem>[
  NewsItem(
    title: 'EA SPORTS FC 27: disponibile il Title Update 1.0.3',
    summary: 'Piccolo aggiornamento correttivo per Ultimate Team, The Grounds e Carriera. '
        'Aggiorna il gioco prima della partita di stasera.',
    url: 'https://www.ea.com/games/ea-sports-fc/fc-27/news/title-update-v1-0-3',
    source: 'EA SPORTS',
    category: 'aggiornamenti',
    publishedAt: DateTime(2026, 10, 2),
  ),
  NewsItem(
    title: 'FVPA: aperte le iscrizioni ai tornei Pro Club su FC 27',
    summary: 'La Football Virtual Pro Association apre le competizioni 11vs11 '
        'per la nuova stagione su PlayStation, Xbox e PC.',
    url: 'https://fvpa.net/',
    source: 'FVPA',
    category: 'tornei',
    publishedAt: DateTime(2026, 10, 1),
  ),
  NewsItem(
    title: 'FC 27 rivoluziona Ultimate Team: Fan Gallery e SBC semplificate',
    summary: 'Più personalizzazione, evoluzioni ramificate e una Power Curve rallentata: '
        'ecco le novità di Ultimate Team.',
    url: 'https://www.everyeye.it/articoli/speciale-fc-27-rivoluziona-ultimate-team-fan-gallery-sbc-semplificate-premi-ricchi-67453.html',
    source: 'Everyeye.it',
    category: 'ultimate_team',
    publishedAt: DateTime(2026, 9, 28),
  ),
];
