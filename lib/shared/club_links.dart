import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';

/// Tipi di contatto supportati (colonna `kind` della tabella `club_links`).
enum LinkKind {
  instagram('Instagram', Icons.camera_alt_rounded),
  whatsapp('WhatsApp', Icons.chat_rounded),
  tiktok('TikTok', Icons.music_note_rounded),
  youtube('YouTube', Icons.play_circle_fill_rounded),
  twitch('Twitch', Icons.live_tv_rounded),
  discord('Discord', Icons.headset_mic_rounded),
  sito('Sito web', Icons.language_rounded);

  const LinkKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static LinkKind parse(String v) =>
      values.firstWhere((k) => k.name == v, orElse: () => LinkKind.sito);
}

class ClubLink {
  const ClubLink({required this.kind, required this.url});
  final LinkKind kind;
  final String url;
}

abstract class ClubLinksRepository {
  Future<List<ClubLink>> load();
  Future<void> saveAll(List<ClubLink> links);
}

final clubLinksRepositoryProvider = Provider<ClubLinksRepository>((ref) {
  if (AppConfig.isDemo) return DemoClubLinksRepository();
  return _SupabaseClubLinksRepository(ref);
});

final clubLinksProvider = FutureProvider<List<ClubLink>>(
  (ref) => ref.watch(clubLinksRepositoryProvider).load(),
);

class _SupabaseClubLinksRepository implements ClubLinksRepository {
  _SupabaseClubLinksRepository(this._ref);
  final Ref _ref;

  @override
  Future<List<ClubLink>> load() async {
    final rows = await _ref
        .read(supabaseProvider)
        .from('club_links')
        .select()
        .order('sort_order');
    return [
      for (final r in rows)
        ClubLink(
          kind: LinkKind.parse(r['kind'] as String),
          url: r['url'] as String,
        ),
    ];
  }

  /// Sostituisce l'intera lista (sono pochi elementi, gestiti solo dal Direttivo).
  @override
  Future<void> saveAll(List<ClubLink> links) async {
    final table = _ref.read(supabaseProvider).from('club_links');
    await table.delete().not('id', 'is', null);
    if (links.isEmpty) return;
    await table.insert([
      for (final (i, l) in links.indexed)
        {'kind': l.kind.name, 'url': l.url, 'sort_order': i},
    ]);
  }
}

class DemoClubLinksRepository implements ClubLinksRepository {
  var _links = const [
    ClubLink(kind: LinkKind.instagram, url: 'https://instagram.com/'),
    ClubLink(kind: LinkKind.whatsapp, url: 'https://wa.me/'),
    ClubLink(kind: LinkKind.youtube, url: 'https://youtube.com/'),
    ClubLink(
      kind: LinkKind.sito,
      url: 'https://fabioruggieri13-debug.github.io/MILANAC/',
    ),
  ];

  @override
  Future<List<ClubLink>> load() async => _links;

  @override
  Future<void> saveAll(List<ClubLink> links) async =>
      _links = List.unmodifiable(links);
}
