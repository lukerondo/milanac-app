import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import 'club_links.dart';

/// Editor dei contatti social (solo Direttivo).
class ClubLinksEditorPage extends ConsumerStatefulWidget {
  const ClubLinksEditorPage({super.key, required this.initial});
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
  late final List<_Row> _rows = [
    for (final l in widget.initial) _Row(l.kind, l.url),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.url.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final links = [
      for (final r in _rows)
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONTATTI SOCIAL'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text(
              'SALVA',
              style: TextStyle(color: MilanacColors.gold),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: MilanacColors.red,
        onPressed: () =>
            setState(() => _rows.add(_Row(LinkKind.instagram, ''))),
        child: const Icon(Icons.add_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (final r in _rows)
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
                      onChanged: (k) => setState(() => r.kind = k ?? r.kind),
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
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => setState(() {
                        _rows.remove(r);
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
