import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'news_item.dart';

/// Immagine in testa alla notizia: la foto della fonte se disponibile,
/// altrimenti una copertina "EA SPORTS FC 27" disegnata (colore per categoria).
class NewsImage extends StatelessWidget {
  const NewsImage({
    super.key,
    required this.item,
    this.height = 150,
    this.compact = false,
  });
  final NewsItem item;
  final double height;

  /// Miniatura (card stretta della Home): copertina semplificata.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cover = NewsCover(
      category: item.category,
      height: height,
      compact: compact,
    );
    final url = item.imageUrl;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url == null || url.isEmpty
          ? cover
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => cover,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : cover,
            ),
    );
  }
}

class NewsCover extends StatelessWidget {
  const NewsCover({
    super.key,
    required this.category,
    this.height = 150,
    this.compact = false,
  });
  final String category;
  final double height;
  final bool compact;

  static (Color, Color, IconData, String) styleFor(String category) =>
      switch (category) {
        'aggiornamenti' => (
          const Color(0xFF1F6FEB),
          const Color(0xFF0B1A33),
          Icons.system_update_rounded,
          'AGGIORNAMENTO',
        ),
        'tornei' => (
          MilanacColors.gold,
          const Color(0xFF2A1F05),
          Icons.emoji_events_rounded,
          'TORNEI',
        ),
        'ultimate_team' => (
          const Color(0xFF12B886),
          const Color(0xFF062A20),
          Icons.style_rounded,
          'ULTIMATE TEAM',
        ),
        _ => (
          MilanacColors.red,
          const Color(0xFF2A060C),
          Icons.groups_rounded,
          'PRO CLUBS',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final (accent, dark, icon, label) = styleFor(category);
    if (compact) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _CoverPainter(accent: accent, dark: dark),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: Colors.white.withValues(alpha: .9)),
                const SizedBox(height: 2),
                const Text(
                  'FC 27',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CoverPainter(accent: accent, dark: dark),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'EA SPORTS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        fontSize: 12,
                      ),
                    ),
                    const FittedBox(
                      child: Text(
                        'FC 27',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 54,
                          height: 1,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: accent.computeLuminance() > .5
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, size: 72, color: Colors.white.withValues(alpha: .85)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sfondo: gradiente scuro, luce da stadio e linee del campo in prospettiva.
class _CoverPainter extends CustomPainter {
  _CoverPainter({required this.accent, required this.dark});
  final Color accent;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [dark, Colors.black],
        ).createShader(rect),
    );
    // Riflettore in alto a destra.
    canvas.drawCircle(
      Offset(size.width * .85, -size.height * .1),
      size.width * .6,
      Paint()
        ..shader =
            RadialGradient(
              colors: [accent.withValues(alpha: .45), Colors.transparent],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * .85, -size.height * .1),
                radius: size.width * .6,
              ),
            ),
    );
    // Linee del campo in prospettiva.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final vanish = Offset(size.width * .6, -size.height * .6);
    for (var i = -4; i <= 8; i++) {
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, size.height), vanish, line);
    }
    for (var j = 1; j <= 3; j++) {
      final y = size.height * (1 - pow(.55, j));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Barra colorata in basso.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 4, size.width, 4),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _CoverPainter old) =>
      old.accent != accent || old.dark != dark;
}
