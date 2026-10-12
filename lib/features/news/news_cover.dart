import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../carta/card_colors.dart';
import 'news_item.dart';

/// Immagine della notizia: la foto della fonte se disponibile, altrimenti una
/// copertina "EA SPORTS FC 27" disegnata, nera e oro, con l'icona della categoria.
class NewsImage extends StatelessWidget {
  const NewsImage({
    super.key,
    required this.item,
    this.height = 150,
    this.compact = false,
  });
  final NewsItem item;
  final double height;

  /// Miniatura (riga della notizia): copertina semplificata.
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

/// Copertina disegnata (colori fissi: è un'immagine, uguale nei due temi).
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

  static (IconData, String) styleFor(String category) => switch (category) {
    'aggiornamenti' => (Icons.system_update_rounded, 'AGGIORNAMENTO'),
    'console' => (Icons.sports_esports_rounded, 'CONSOLE'),
    'tornei' => (Icons.emoji_events_rounded, 'TORNEI'),
    'ultimate_team' => (Icons.style_rounded, 'ULTIMATE TEAM'),
    _ => (Icons.groups_rounded, 'PRO CLUBS'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, label) = styleFor(category);
    if (compact) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _CoverPainter(),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: CardColors.goldText),
                  const SizedBox(height: 2),
                  const Text(
                    'FC 27',
                    style: TextStyle(
                      fontFamily: sportFont,
                      color: MilanacColors.ivory,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CoverPainter(),
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
                        color: MilanacColors.ivoryMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        fontSize: 12,
                      ),
                    ),
                    const FittedBox(
                      child: Text(
                        'FC 27',
                        style: TextStyle(
                          fontFamily: sportFont,
                          color: MilanacColors.ivory,
                          fontWeight: FontWeight.w700,
                          fontSize: 54,
                          height: 1,
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
                        color: MilanacColors.gold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: MilanacColors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, size: 72, color: CardColors.goldText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sfondo: nero caldo, luce da stadio d'oro e linee del campo in prospettiva.
class _CoverPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CardColors.neroOroLight, MilanacColors.black],
        ).createShader(rect),
    );
    // Riflettore in alto a destra.
    final light = Offset(size.width * .85, -size.height * .1);
    canvas.drawCircle(
      light,
      size.width * .6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            MilanacColors.gold.withValues(alpha: .4),
            MilanacColors.gold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: light, radius: size.width * .6)),
    );
    // Linee del campo in prospettiva.
    final line = Paint()
      ..color = MilanacColors.ivory.withValues(alpha: .08)
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
    // Filo d'oro in basso.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 3, size.width, 3),
      Paint()..color = MilanacColors.gold,
    );
  }

  @override
  bool shouldRepaint(covariant _CoverPainter old) => false;
}
