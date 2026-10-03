import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';

/// Sezioni che usano i link condivisi (tabella `shared_links`).
enum LinkCategory { musica, build }

/// Link condiviso da un membro: playlist, video di una build…
class SharedLink {
  const SharedLink({
    required this.id,
    required this.category,
    required this.title,
    required this.url,
    this.note,
    this.tag,
    this.createdBy,
    this.sortOrder = 0,
  });

  final String id;
  final LinkCategory category;
  final String title;
  final String url;
  final String? note;

  /// Etichetta libera (per le build: il ruolo, es. ATT).
  final String? tag;
  final String? createdBy;
  final int sortOrder;

  factory SharedLink.fromMap(Map<String, dynamic> m) => SharedLink(
    id: m['id'] as String,
    category: LinkCategory.values.byName(m['category'] as String),
    title: m['title'] as String,
    url: m['url'] as String,
    note: m['note'] as String?,
    tag: m['tag'] as String?,
    createdBy: m['created_by'] as String?,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'category': category.name,
    'title': title,
    'url': url,
    'note': note,
    'tag': tag,
    'sort_order': sortOrder,
  };
}

abstract class SharedLinksRepository {
  Stream<List<SharedLink>> watch(LinkCategory category);

  /// Crea il link se [SharedLink.id] è vuoto, altrimenti lo aggiorna.
  Future<void> save(SharedLink link);
  Future<void> delete(String id);
}

final sharedLinksRepositoryProvider = Provider<SharedLinksRepository>((ref) {
  if (AppConfig.isDemo) return DemoSharedLinksRepository();
  return _SupabaseSharedLinksRepository(ref);
});

final sharedLinksProvider =
    StreamProvider.family<List<SharedLink>, LinkCategory>(
      (ref, category) =>
          ref.watch(sharedLinksRepositoryProvider).watch(category),
    );

class _SupabaseSharedLinksRepository implements SharedLinksRepository {
  _SupabaseSharedLinksRepository(this._ref);
  final Ref _ref;

  @override
  Stream<List<SharedLink>> watch(LinkCategory category) => _ref
      .read(supabaseProvider)
      .from('shared_links')
      .stream(primaryKey: ['id'])
      .eq('category', category.name)
      .order('created_at')
      .map(
        (rows) =>
            rows.map(SharedLink.fromMap).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      );

  @override
  Future<void> save(SharedLink link) async {
    final table = _ref.read(supabaseProvider).from('shared_links');
    if (link.id.isEmpty) {
      await table.insert(link.toMap());
    } else {
      await table.update(link.toMap()).eq('id', link.id);
    }
  }

  @override
  Future<void> delete(String id) async {
    await _ref
        .read(supabaseProvider)
        .from('shared_links')
        .delete()
        .eq('id', id);
  }
}

class DemoSharedLinksRepository implements SharedLinksRepository {
  final _links = <SharedLink>[
    const SharedLink(
      id: 'l1',
      category: LinkCategory.musica,
      title: 'Le canzoni più iconiche di FIFA',
      url: 'https://www.youtube.com/results?search_query=canzoni+iconiche+FIFA+soundtrack',
      note: 'Compilation su YouTube',
    ),
    const SharedLink(
      id: 'l2',
      category: LinkCategory.musica,
      title: 'Playlist FIFA su Spotify',
      url: 'https://open.spotify.com/search/FIFA%20soundtrack',
      note: "Si apre nell'app di Spotify",
      sortOrder: 1,
    ),
    const SharedLink(
      id: 'l3',
      category: LinkCategory.build,
      title: 'La build da attaccante più forte',
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      note: 'Creator: esempio',
      tag: 'ATT',
      createdBy: 'p2',
    ),
  ];
  final _changes = StreamController<void>.broadcast();
  var _nextId = 100;

  List<SharedLink> _of(LinkCategory c) =>
      _links.where((l) => l.category == c).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Stream<List<SharedLink>> watch(LinkCategory category) async* {
    yield _of(category);
    yield* _changes.stream.map((_) => _of(category));
  }

  @override
  Future<void> save(SharedLink link) async {
    final i = _links.indexWhere((l) => l.id == link.id);
    if (i >= 0) {
      _links[i] = link;
    } else {
      _links.add(
        SharedLink(
          id: 'l${_nextId++}',
          category: link.category,
          title: link.title,
          url: link.url,
          note: link.note,
          tag: link.tag,
          createdBy: 'demo',
          sortOrder: _links.length,
        ),
      );
    }
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    _links.removeWhere((l) => l.id == id);
    _changes.add(null);
  }
}

Future<void> openSharedLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Finestra per aggiungere o modificare un link. [tags], se indicati, diventano una scelta.
Future<SharedLink?> showSharedLinkEditor(
  BuildContext context, {
  required LinkCategory category,
  SharedLink? link,
  List<String> tags = const [],
  String titleHint = '',
  String noteLabel = 'Nota (facoltativa)',
}) => showDialog<SharedLink>(
  context: context,
  builder: (_) => _SharedLinkDialog(
    category: category,
    link: link,
    tags: tags,
    titleHint: titleHint,
    noteLabel: noteLabel,
  ),
);

class _SharedLinkDialog extends StatefulWidget {
  const _SharedLinkDialog({
    required this.category,
    required this.link,
    required this.tags,
    required this.titleHint,
    required this.noteLabel,
  });
  final LinkCategory category;
  final SharedLink? link;
  final List<String> tags;
  final String titleHint;
  final String noteLabel;

  @override
  State<_SharedLinkDialog> createState() => _SharedLinkDialogState();
}

class _SharedLinkDialogState extends State<_SharedLinkDialog> {
  late final _title = TextEditingController(text: widget.link?.title);
  late final _url = TextEditingController(text: widget.link?.url);
  late final _note = TextEditingController(text: widget.link?.note);
  late String? _tag =
      widget.link?.tag ?? (widget.tags.isEmpty ? null : widget.tags.first);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    var url = _url.text.trim();
    if (url.isNotEmpty && !url.contains('://')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Inserisci un titolo.');
      return;
    }
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      setState(() => _error = 'Link non valido.');
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(
      context,
      SharedLink(
        id: widget.link?.id ?? '',
        category: widget.category,
        title: _title.text.trim(),
        url: url,
        note: note.isEmpty ? null : note,
        tag: _tag,
        createdBy: widget.link?.createdBy,
        sortOrder: widget.link?.sortOrder ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.link == null ? 'Nuovo link' : 'Modifica link'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.tags.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _tag,
                decoration: const InputDecoration(labelText: 'Ruolo'),
                items: [
                  for (final t in widget.tags)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _tag = v),
              ),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Titolo',
                hintText: widget.titleHint,
              ),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link',
                hintText: 'https://www.youtube.com/…',
              ),
            ),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: widget.noteLabel),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Salva')),
      ],
    );
  }
}
