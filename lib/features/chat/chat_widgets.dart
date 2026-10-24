import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'chat_repository.dart';

/// Riquadro con l'icona del canale (tavole 12 e 13): oro tenue se ci sono novità,
/// neutro altrimenti, oro pieno con il lucchetto per la Sala Direttivo. [palette]
/// fissa i colori per le parti sempre scure (la barra della conversazione).
class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    this.size = 46,
    this.radius = 14,
    this.highlighted = false,
    this.palette,
  });
  final Channel channel;
  final double size;
  final double radius;
  final bool highlighted;
  final AppPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? context.pal;
    final (background, foreground) = channel.direttivoOnly
        ? (p.accent, p.onAccent)
        : highlighted
        ? (p.accentTint, p.accentText)
        : (p.surfaceHigh, p.textSecondary);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(channel.iconData, size: size * .48, color: foreground),
    );
  }
}

/// Ora di un messaggio negli elenchi: "08:55" oggi, "Ieri", poi "12 ott".
String chatWhen(DateTime t, {bool withTime = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = DateFormat('HH:mm').format(t);
  if (day == today) return time;
  final label = day == today.subtract(const Duration(days: 1))
      ? 'Ieri'
      : DateFormat(
          day.year == today.year ? 'd MMM' : 'd MMM y',
          'it',
        ).format(t);
  return withTime ? '$label $time' : label;
}

/// Il pezzo di testo da mostrare in un risultato della ricerca: se la parola
/// cercata è lontana dall'inizio, si parte poco prima ("…").
String searchSnippet(String text, String query) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final at = flat.toLowerCase().indexOf(query.trim().toLowerCase());
  if (at <= 40) return flat;
  final space = flat.lastIndexOf(' ', at - 20);
  return '…${flat.substring(space < 0 ? at - 20 : space + 1)}';
}

/// [text] a pezzi, con le parti uguali a [query] (maiuscole e minuscole non
/// contano) nello stile [hit].
List<TextSpan> highlightMatches(
  String text,
  String query, {
  required TextStyle hit,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var from = 0;
  while (true) {
    final at = lower.indexOf(q, from);
    if (at < 0) break;
    if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
    spans.add(TextSpan(text: text.substring(at, at + q.length), style: hit));
    from = at + q.length;
  }
  if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
  return spans;
}

/// Un carattere emoji (faccine, simboli, bandiere, toni della pelle...).
bool _isEmojiRune(int r) =>
    (r >= 0x1F000 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2300 && r <= 0x23FF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2190 && r <= 0x21FF) ||
    (r >= 0x25A0 && r <= 0x25FF) ||
    const {
      0x00A9, 0x00AE, 0x203C, 0x2049, 0x2122, 0x2139, //
      0x24C2, 0x2934, 0x2935, 0x3030, 0x303D, 0x3297, 0x3299,
    }.contains(r);

/// Ciò che unisce o varia le emoji (giunzioni, varianti, tasti, bandiere regionali).
bool _isEmojiJoiner(int r) =>
    r == 0x200D ||
    r == 0xFE0E ||
    r == 0xFE0F ||
    r == 0x20E3 ||
    (r >= 0xE0020 && r <= 0xE007F);

/// Un messaggio fatto solo di una, due o tre emoji (si mostra grande, senza bolla).
bool isEmojiOnly(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty || t.characters.length > 3) return false;
  var emoji = 0;
  for (final r in t.runes) {
    if (_isEmojiRune(r)) {
      emoji++;
    } else if (!_isEmojiJoiner(r) && r != 0x20) {
      return false;
    }
  }
  return emoji > 0;
}
