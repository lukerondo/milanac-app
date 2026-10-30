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
