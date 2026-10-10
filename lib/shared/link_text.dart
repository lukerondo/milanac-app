import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';

final _linkPattern = RegExp(
  r'(https?://[^\s<>"]+|www\.[^\s<>"]+)',
  caseSensitive: false,
);

/// Pezzo di testo: se [isLink] si apre nel browser.
class TextPiece {
  const TextPiece(this.text, {this.isLink = false});
  final String text;
  final bool isLink;

  Uri get uri => Uri.parse(text.startsWith('www.') ? 'https://$text' : text);
}

/// Divide [text] in testo normale e link. La punteggiatura finale (".", ",", ")")
/// resta fuori dal link, a meno che la parentesi faccia parte dell'indirizzo.
List<TextPiece> splitLinks(String text) {
  final pieces = <TextPiece>[];
  var last = 0;
  for (final m in _linkPattern.allMatches(text)) {
    var link = m.group(0)!;
    var end = m.end;
    while (link.isNotEmpty && '.,;:!?)]}\'"'.contains(link[link.length - 1])) {
      if (link.endsWith(')') &&
          '('.allMatches(link).length >= ')'.allMatches(link).length) {
        break;
      }
      link = link.substring(0, link.length - 1);
      end--;
    }
    if (m.start > last) pieces.add(TextPiece(text.substring(last, m.start)));
    pieces.add(TextPiece(link, isLink: true));
    last = end;
  }
  if (last < text.length) pieces.add(TextPiece(text.substring(last)));
  return pieces;
}

/// Testo con i link cliccabili (si aprono fuori dall'app).
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, this.style, this.linkColor});
  final String text;
  final TextStyle? style;
  final Color? linkColor;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Non riesco ad aprire $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final pieces = splitLinks(widget.text);
    if (pieces.length == 1 && !pieces.first.isLink) {
      return Text(widget.text, style: widget.style);
    }
    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: widget.linkColor ?? MilanacColors.gold,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor ?? MilanacColors.gold,
    );
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final p in pieces)
            if (p.isLink)
              TextSpan(
                text: p.text,
                style: linkStyle,
                recognizer: () {
                  final r = TapGestureRecognizer()..onTap = () => _open(p.uri);
                  _recognizers.add(r);
                  return r;
                }(),
              )
            else
              TextSpan(text: p.text),
        ],
      ),
    );
  }
}
