import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';

/// Sezioni che usano i link condivisi (tabella `shared_links`):
/// la colonna sonora e i video dei creator di Mondo Proclub.
enum LinkCategory { musica, video }

/// I video li propongono i giocatori; li pubblica il Direttivo.
enum LinkStatus { proposto, pubblicato }

/// Link condiviso da un membro: playlist, video di un creator…
class SharedLink {
  const SharedLink({
    required this.id,
    required this.category,
    required this.title,
    required this.url,
    this.note,
    this.tag,
    this.createdBy,
    this.createdAt,
    this.sortOrder = 0,
    this.status = LinkStatus.pubblicato,
    this.publishedBy,
    this.publishedAt,
  });

  final String id;
  final LinkCategory category;
  final String title;
  final String url;
  final String? note;

  /// Etichetta libera (per i video: il ruolo di cui parlano, es. ATT).
  final String? tag;
  final String? createdBy;
  final DateTime? createdAt;
  final int sortOrder;
  final LinkStatus status;
  final String? publishedBy;
  final DateTime? publishedAt;

  bool get isPublished => status == LinkStatus.pubblicato;

  factory SharedLink.fromMap(Map<String, dynamic> m) => SharedLink(
    id: m['id'] as String,
    category: LinkCategory.values.byName(m['category'] as String),
    title: m['title'] as String,
    url: m['url'] as String,
    note: m['note'] as String?,
    tag: m['tag'] as String?,
    createdBy: m['created_by'] as String?,
    createdAt: m['created_at'] == null
        ? null
        : DateTime.parse(m['created_at'] as String).toLocal(),
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    status:
        LinkStatus.values.asNameMap()[m['status']] ?? LinkStatus.pubblicato,
    publishedBy: m['published_by'] as String?,
    publishedAt: m['published_at'] == null
        ? null
        : DateTime.parse(m['published_at'] as String).toLocal(),
  );

  Map<String, dynamic> toMap() => {
    'category': category.name,
    'title': title,
    'url': url,
    'note': note,
    'tag': tag,
    'sort_order': sortOrder,
    'status': status.name,
  };

  SharedLink copyWith({
    String? title,
    String? url,
    String? note,
    String? tag,
    LinkStatus? status,
    String? publishedBy,
    DateTime? publishedAt,
  }) => SharedLink(
    id: id,
    category: category,
    title: title ?? this.title,
    url: url ?? this.url,
    note: note ?? this.note,
    tag: tag ?? this.tag,
    createdBy: createdBy,
    createdAt: createdAt,
    sortOrder: sortOrder,
    status: status ?? this.status,
    publishedBy: publishedBy ?? this.publishedBy,
    publishedAt: publishedAt ?? this.publishedAt,
  );
}

abstract class SharedLinksRepository {
  /// I link di una categoria visibili a chi è collegato (i video proposti
  /// li vedono solo l'autore e il Direttivo).
  Stream<List<SharedLink>> watch(LinkCategory category);

  /// Crea il link se [SharedLink.id] è vuoto, altrimenti lo aggiorna.
  /// Un giocatore che aggiunge un video lo sta proponendo: lo pubblica il Direttivo.
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
  DemoSharedLinksRepository() {
    final now = DateTime.now();
    _links.addAll([
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
      SharedLink(
        id: 'l3',
        category: LinkCategory.video,
        title: 'La build da attaccante più forte',
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        note: 'Creator: esempio',
        tag: 'ATT',
        createdBy: 'p2',
        createdAt: now.subtract(const Duration(days: 3)),
        publishedBy: 'demo',
        publishedAt: now.subtract(const Duration(days: 2)),
      ),
      SharedLink(
        id: 'l4',
        category: LinkCategory.video,
        title: 'Difendere in 11 contro 11: i movimenti del DC',
        url: 'https://youtu.be/abc123',
        note: 'Creator: Pro Club Italia',
        tag: 'DC',
        createdBy: 'p3',
        createdAt: now.subtract(const Duration(hours: 5)),
        status: LinkStatus.proposto,
        sortOrder: 1,
      ),
    ]);
  }

  final _links = <SharedLink>[];
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
    final now = DateTime.now();
    final i = _links.indexWhere((l) => l.id == link.id);
    if (i >= 0) {
      final old = _links[i];
      // Come il database: chi pubblica resta registrato.
      final published = link.isPublished && !old.isPublished;
      _links[i] = link.copyWith(
        publishedBy: published ? 'demo' : null,
        publishedAt: published ? now : null,
      );
    } else {
      // In demo si è Direttivo: i propri video sono pubblicati subito.
      _links.add(
        SharedLink(
          id: 'l${_nextId++}',
          category: link.category,
          title: link.title,
          url: link.url,
          note: link.note,
          tag: link.tag,
          createdBy: 'demo',
          createdAt: now,
          sortOrder: _links.length,
          status: link.status,
          publishedBy: link.isPublished ? 'demo' : null,
          publishedAt: link.isPublished ? now : null,
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
  String title = '',
  String titleHint = '',
  String noteLabel = 'Nota (facoltativa)',
  String tagLabel = 'Ruolo',
}) => showDialog<SharedLink>(
  context: context,
  builder: (_) => _SharedLinkDialog(
    category: category,
    link: link,
    tags: tags,
    title: title,
    titleHint: titleHint,
    noteLabel: noteLabel,
    tagLabel: tagLabel,
  ),
);

class _SharedLinkDialog extends StatefulWidget {
  const _SharedLinkDialog({
    required this.category,
    required this.link,
    required this.tags,
    required this.title,
    required this.titleHint,
    required this.noteLabel,
    required this.tagLabel,
  });
  final LinkCategory category;
  final SharedLink? link;
  final List<String> tags;
  final String title;
  final String titleHint;
  final String noteLabel;
  final String tagLabel;

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
    final link = widget.link;
    Navigator.pop(
      context,
      link == null
          ? SharedLink(
              id: '',
              category: widget.category,
              title: _title.text.trim(),
              url: url,
              note: note.isEmpty ? null : note,
              tag: _tag,
            )
          : SharedLink(
              id: link.id,
              category: link.category,
              title: _title.text.trim(),
              url: url,
              note: note.isEmpty ? null : note,
              tag: _tag,
              createdBy: link.createdBy,
              createdAt: link.createdAt,
              sortOrder: link.sortOrder,
              status: link.status,
              publishedBy: link.publishedBy,
              publishedAt: link.publishedAt,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title.isNotEmpty
            ? widget.title
            : widget.link == null
            ? 'Nuovo link'
            : 'Modifica link',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.tags.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _tag,
                isExpanded: true,
                decoration: InputDecoration(labelText: widget.tagLabel),
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
