import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'parchment.dart';
import 'rules_repository.dart';

/// Il regolamento su pergamena: intestazione, articoli, firma.
/// Usato dalla sezione Regolamento e dalla pagina di accettazione.
class RulesReader extends StatelessWidget {
  const RulesReader({
    super.key,
    required this.version,
    this.controller,
    this.closing,
    this.bottomPadding = 24,
  });
  final RulesVersion version;
  final ScrollController? controller;

  /// Testo in chiusura, prima della firma (es. la formula di accettazione).
  final String? closing;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final date = version.publishedAt == null
        ? null
        : DateFormat('d MMMM yyyy', 'it').format(version.publishedAt!);
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(26, 26, 26, bottomPadding),
      children: [
        ParchmentHeader(
          title: 'Regolamento',
          note: date == null
              ? 'Versione ${version.number}'
              : 'Versione ${version.number} · pubblicata il $date',
        ),
        for (final a in version.articles)
          ParchmentArticle(title: a.title, body: a.body),
        if (version.articles.isEmpty)
          const ParchmentParagraph(
            'Il Direttivo non ha ancora scritto gli articoli del regolamento.',
          ),
        if (closing != null) ...[
          const ParchmentOrnament(),
          ParchmentParagraph(closing!),
        ],
        const ParchmentSignature(),
      ],
    );
  }
}

/// La storia del club su pergamena.
class StoryReader extends StatelessWidget {
  const StoryReader({super.key, required this.text, this.controller});
  final String text;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
      children: [
        const ParchmentHeader(title: 'La nostra storia'),
        if (paragraphs.isEmpty)
          const ParchmentParagraph(
            'La storia del club deve ancora essere scritta.',
          )
        else
          for (final (i, p) in paragraphs.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ParchmentParagraph(p, dropCap: i == 0),
            ),
        const ParchmentSignature(text: 'I fondatori'),
      ],
    );
  }
}
