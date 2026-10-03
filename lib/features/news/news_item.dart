class NewsItem {
  const NewsItem({
    required this.title,
    required this.summary,
    required this.url,
    required this.source,
    required this.category,
    required this.publishedAt,
    this.imageUrl,
  });

  final String title;
  final String summary;
  final String url;
  final String source;
  final String category;
  final DateTime publishedAt;
  final String? imageUrl;

  bool get isGameUpdate => category == 'aggiornamenti';

  factory NewsItem.fromMap(Map<String, dynamic> m) => NewsItem(
        title: m['title'] as String,
        summary: (m['summary'] as String?) ?? '',
        url: m['url'] as String,
        source: m['source'] as String,
        category: m['category'] as String,
        publishedAt: DateTime.parse(m['published_at'] as String),
        imageUrl: m['image_url'] as String?,
      );
}

/// Categorie mostrate come filtri nella Home.
const newsCategories = <String, String>{
  'tutte': 'Tutte',
  'tornei': 'Tornei',
  'aggiornamenti': 'Aggiornamenti FC 27',
  'ultimate_team': 'Ultimate Team',
  'pro_clubs': 'Pro Clubs',
};
