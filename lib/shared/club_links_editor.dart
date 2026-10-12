import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/theme.dart';
import 'async_view.dart';
import 'club_links.dart';
import 'ui.dart';

/// Editor dei contatti social (solo Direttivo).
class ClubLinksEditorPage extends ConsumerStatefulWidget {
  const ClubLinksEditorPage({super.key, required this.initial});

  /// I contatti che aveva chi apre l'editor. L'editor parte comunque dall'elenco
  /// caricato davvero dal server: con un caricamento fallito (elenco vuoto) il
  /// salvataggio cancellerebbe tutti i contatti.
  final List<ClubLink> initial;

  @override
  ConsumerState<ClubLinksEditorPage> createState() =>
      _ClubLinksEditorPageState();
}

class _Row {
  _Row(this.kind, String url) : url = TextEditingController(text: url);
  LinkKind kind;
  final TextEditingController url;
}

class _ClubLinksEditorPageState extends ConsumerState<ClubLinksEditorPage> {
  /// null finché l'elenco dei contatti non è arrivato.
  List<_Row>? _rows;
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows ?? const <_Row>[]) {
      r.url.dispose();
    }
    super.dispose();
  }

  Future<void> _save(List<_Row> rows) async {
    final links = [
      for (final r in rows)
        if (r.url.text.trim().isNotEmpty)
          ClubLink(kind: r.kind, url: _normalize(r.url.text)),
    ];
    setState(() => _saving = true);
    try {
      await ref.read(clubLinksRepositoryProvider).saveAll(links);
      ref.invalidate(clubLinksProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
          ),
        );
      }
    }
  }

  static String _normalize(String url) {
    final u = url.trim();
    return u.startsWith('http://') || u.startsWith('https://')
        ? u
        : 'https://$u';
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(clubLinksProvider);
    if (_rows == null && loaded.hasValue) {
      _rows = [for (final l in loaded.requireValue) _Row(l.kind, l.url)];
    }
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONTATTI SOCIAL'),
        flexibleSpace: const Align(
          alignment: Alignment.topCenter,
          child: GoldRule(),
        ),
        actions: [
          // La barra è sempre scura: l'oro chiaro si legge in tutti e due i temi.
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: MilanacColors.goldLight,
            ),
            onPressed: _saving || rows == null ? null : () => _save(rows),
            child: const Text('SALVA'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: rows == null
          ? null
          : FloatingActionButton(
              tooltip: 'Aggiungi un contatto',
              onPressed: () =>
                  setState(() => rows.add(_Row(LinkKind.instagram, ''))),
              child: const Icon(Icons.add_rounded),
            ),
      body: rows == null
          ? AsyncView(
              value: loaded,
              onRetry: () => ref.invalidate(clubLinksProvider),
              data: (_) => const SizedBox.shrink(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final r in rows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          DropdownButton<LinkKind>(
                            value: r.kind,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final k in LinkKind.values)
                                DropdownMenuItem(value: k, child: Icon(k.icon)),
                            ],
                            onChanged: (k) =>
                                setState(() => r.kind = k ?? r.kind),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: r.url,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: r.kind.label,
                                hintText: 'https://…',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Togli il contatto',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => setState(() {
                              rows.remove(r);
                              r.url.dispose();
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
