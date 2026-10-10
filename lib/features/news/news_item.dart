class NewsItem {
  const NewsItem({
    required this.title,
    required this.summary,
    required this.url,
    required this.source,
    required this.category,
    required this.publishedAt,
    this.imageUrl,
    this.platform,
  });

  final String title;
  final String summary;
  final String url;
  final String source;
  final String category;
  final DateTime publishedAt;
  final String? imageUrl;

  /// Solo per le notizie sulle console: ps5 o xbox.
  final String? platform;

  bool get isGameUpdate => category == 'aggiornamenti';
  bool get isConsoleUpdate => category == 'console';

  /// Uscita negli ultimi giorni: vale la pena avvisare.
  bool isRecent(DateTime now) => now.difference(publishedAt).inDays <= 3;

  factory NewsItem.fromMap(Map<String, dynamic> m) => NewsItem(
    title: m['title'] as String,
    summary: (m['summary'] as String?) ?? '',
    url: m['url'] as String,
    source: m['source'] as String,
    category: m['category'] as String,
    publishedAt: DateTime.parse(m['published_at'] as String),
    imageUrl: m['image_url'] as String?,
    platform: m['platform'] as String?,
  );
}

/// Categorie mostrate come filtri nelle notizie.
const newsCategories = <String, String>{
  'tutte': 'Tutte',
  'aggiornamenti': 'Aggiornamenti FC 27',
  'console': 'Console',
  'tornei': 'Tornei',
  'pro_clubs': 'Pro Clubs',
  'ultimate_team': 'Ultimate Team',
};

/// Nome della piattaforma come la chiamano i giocatori.
String platformLabel(String? platform) => switch (platform) {
  'ps5' => 'PlayStation',
  'xbox' => 'Xbox',
  'pc' => 'PC',
  _ => 'Console',
};
