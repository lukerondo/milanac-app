import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/ui.dart';
import 'rules_repository.dart';

/// "Versione 1 · pubblicata il 1 settembre 2026".
String rulesVersionLabel(RulesVersion version) {
  final at = version.publishedAt;
  return at == null
      ? 'Versione ${version.number}'
      : 'Versione ${version.number} · pubblicata il '
            '${DateFormat('d MMMM yyyy', 'it').format(at)}';
}

/// L'articolo con l'organigramma (titolo "Organigramma"), se il regolamento ce l'ha.
RulesArticle? organigrammaOf(RulesVersion? version) => version?.articles
    .where((a) => a.title.trim().toLowerCase() == 'organigramma')
    .firstOrNull;

/// Il regolamento in una pagina di lettura su fondo scuro: versione, articoli (con
/// l'organigramma) e, nell'accettazione, la formula finale. Usato dalla sezione
/// Regolamento e dall'accettazione.
class RulesReader extends StatelessWidget {
  const RulesReader({
    super.key,
    required this.version,
    this.controller,
    this.intro,
    this.closing,
    this.showVersion = true,
    this.bottomPadding = 24,
  });
  final RulesVersion version;
  final ScrollController? controller;

  /// Riga introduttiva in cima (es. "Leggilo fino in fondo...").
  final String? intro;

  /// Testo in chiusura (es. la formula di accettazione).
  final String? closing;

  /// false quando versione e data stanno già nella fascia in alto.
  final bool showVersion;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final blocks = <Widget>[
      if (showVersion)
        Text(
          rulesVersionLabel(version),
          style: TextStyle(color: p.textMuted, fontSize: 14),
        ),
      if (intro != null)
        Text(
          intro!,
          style: TextStyle(color: p.textSecondary, fontSize: 16, height: 1.5),
        ),
      for (final a in version.articles)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReaderHeading(a.title),
            const SizedBox(height: 8),
            ReaderBody(a.body),
          ],
        ),
      if (version.articles.isEmpty)
        const ReaderBody(
          'Il Direttivo non ha ancora scritto gli articoli del regolamento.',
        ),
      if (closing != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(color: p.importantBorder, height: 1),
            const SizedBox(height: 16),
            Text(
              closing!,
              style: TextStyle(
                color: p.text,
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
    ];
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPadding),
      children: [
        AppCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, b) in blocks.indexed) ...[
                if (i > 0) const SizedBox(height: 18),
                b,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// La storia del club e, sotto, l'organigramma (dal regolamento).
class StoryReader extends StatelessWidget {
  const StoryReader({
    super.key,
    required this.text,
    this.organigramma,
    this.controller,
    this.bottomPadding = 24,
  });
  final String text;
  final RulesArticle? organigramma;
  final ScrollController? controller;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final org = organigramma;
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      children: [
        AppCard(
          important: true,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Image.asset('assets/images/stemma_256.png', height: 52),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: ReaderHeading('La nostra storia', size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (paragraphs.isEmpty)
                const ReaderBody(
                  'La storia del club deve ancora essere scritta.',
                  size: 16,
                )
              else
                for (final (i, p) in paragraphs.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == paragraphs.length - 1 ? 0 : 12,
                    ),
                    child: ReaderBody(p, size: 16),
                  ),
            ],
          ),
        ),
        if (org != null) ...[
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReaderHeading(org.title, size: 18, gold: false),
                const SizedBox(height: 6),
                ReaderBody(org.body, dividers: true),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Titolo di un articolo: Oswald maiuscolo, in oro.
class ReaderHeading extends StatelessWidget {
  const ReaderHeading(this.text, {super.key, this.size = 19, this.gold = true});
  final String text;
  final double size;
  final bool gold;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: sportFont,
      fontWeight: FontWeight.w600,
      fontSize: size,
      letterSpacing: 1,
      color: gold ? context.pal.accentText : context.pal.text,
    ),
  );
}

/// Testo di un articolo. Le righe "ETICHETTA: valore" (es. l'organigramma)
/// diventano voci con l'etichetta in piccolo sopra il valore.
class ReaderBody extends StatelessWidget {
  const ReaderBody(
    this.text, {
    super.key,
    this.size = 17,
    this.dividers = false,
  });
  final String text;
  final double size;

  /// Filo sottile tra le voci (organigramma nella Storia).
  final bool dividers;

  static final _entry = RegExp(r'^([A-ZÀ-Ý0-9 /\.\-&]{3,60}):\s*(.+)$');

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final lines = [
      for (final l in text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final entries = [for (final l in lines) _entry.firstMatch(l)];
    final isList = entries.isNotEmpty && entries.every((m) => m != null);
    if (!isList) {
      return Text(
        text.trim(),
        style: TextStyle(color: p.text, fontSize: size, height: 1.6),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, m) in entries.indexed)
          Container(
            padding: EdgeInsets.symmetric(vertical: dividers ? 8 : 4),
            decoration: dividers && i < entries.length - 1
                ? BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.divider)),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m!.group(1)!.trim(),
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                  ),
                ),
                Text(
                  m.group(2)!.trim(),
                  style: TextStyle(color: p.text, fontSize: 16, height: 1.4),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
