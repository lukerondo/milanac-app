import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';

const tacticsBucket = 'tactics';

/// Uno schema o una tattica del club (tabella `tactics`).
class Tactic {
  const Tactic({
    required this.id,
    required this.title,
    this.module,
    this.description = '',
    this.imagePath,
    this.localImage,
  });

  final String id;
  final String title;
  final String? module;
  final String description;
  final String? imagePath;

  /// Solo demo: immagine tenuta in memoria.
  final Uint8List? localImage;

  bool get hasImage => imagePath != null || localImage != null;

  factory Tactic.fromMap(Map<String, dynamic> m) => Tactic(
    id: m['id'] as String,
    title: m['title'] as String,
    module: m['module'] as String?,
    description: (m['description'] as String?) ?? '',
    imagePath: m['image_path'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'module': module,
    'description': description,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

abstract class TacticsRepository {
  Stream<List<Tactic>> watchAll();

  /// Crea o aggiorna; se [image] non è null carica la nuova immagine (JPEG).
  Future<void> save(Tactic tactic, {Uint8List? image});
  Future<void> delete(Tactic tactic);
  Future<String> imageUrl(Tactic tactic);
}

final tacticsRepositoryProvider = Provider<TacticsRepository>((ref) {
  if (AppConfig.isDemo) return DemoTacticsRepository();
  return _SupabaseTacticsRepository(ref);
});

final tacticsProvider = StreamProvider<List<Tactic>>(
  (ref) => ref.watch(tacticsRepositoryProvider).watchAll(),
);

final tacticImageUrlProvider = FutureProvider.family<String, String>((
  ref,
  path,
) async {
  final repo = ref.watch(tacticsRepositoryProvider);
  return repo.imageUrl(Tactic(id: '', title: '', imagePath: path));
});

class _SupabaseTacticsRepository implements TacticsRepository {
  _SupabaseTacticsRepository(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseProvider);

  @override
  Stream<List<Tactic>> watchAll() => _client
      .from('tactics')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Tactic.fromMap).toList());

  @override
  Future<void> save(Tactic t, {Uint8List? image}) async {
    var imagePath = t.imagePath;
    if (image != null) {
      final path = '${DateTime.now().microsecondsSinceEpoch}.jpg';
      await _client.storage
          .from(tacticsBucket)
          .uploadBinary(
            path,
            image,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      if (t.imagePath != null) {
        await _client.storage.from(tacticsBucket).remove([t.imagePath!]);
      }
      imagePath = path;
    }
    final values = {...t.toMap(), 'image_path': imagePath};
    if (t.id.isEmpty) {
      await _client.from('tactics').insert(values);
    } else {
      await _client.from('tactics').update(values).eq('id', t.id);
    }
  }

  @override
  Future<void> delete(Tactic t) async {
    if (t.imagePath != null) {
      await _client.storage.from(tacticsBucket).remove([t.imagePath!]);
    }
    await _client.from('tactics').delete().eq('id', t.id);
  }

  @override
  Future<String> imageUrl(Tactic t) => _client.storage
      .from(tacticsBucket)
      .createSignedUrl(t.imagePath!, 60 * 60 * 6);
}

class DemoTacticsRepository implements TacticsRepository {
  final _tactics = <Tactic>[
    const Tactic(
      id: 't1',
      title: 'Pressing alto dopo palla persa',
      module: '4-3-3',
      description:
          'Le due mezzali salgono sul portatore, il CDC copre la linea di passaggio '
          'centrale. Il terzino lato palla accorcia sull\'esterno. Se il pressing '
          'viene superato: tutti dietro la linea della palla.',
    ),
    const Tactic(
      id: 't2',
      title: 'Calcio d\'angolo a rientrare',
      module: 'Piazzati',
      description: 'Blocco sul primo palo, inserimento del DC sul secondo.',
    ),
  ];
  final _changes = StreamController<void>.broadcast();
  var _next = 10;

  @override
  Stream<List<Tactic>> watchAll() async* {
    yield List.of(_tactics);
    yield* _changes.stream.map((_) => List.of(_tactics));
  }

  @override
  Future<void> save(Tactic t, {Uint8List? image}) async {
    final saved = Tactic(
      id: t.id.isEmpty ? 't${_next++}' : t.id,
      title: t.title,
      module: t.module,
      description: t.description,
      localImage: image ?? t.localImage,
    );
    final i = _tactics.indexWhere((x) => x.id == saved.id);
    i >= 0 ? _tactics[i] = saved : _tactics.insert(0, saved);
    _changes.add(null);
  }

  @override
  Future<void> delete(Tactic t) async {
    _tactics.removeWhere((x) => x.id == t.id);
    _changes.add(null);
  }

  @override
  Future<String> imageUrl(Tactic t) async => '';
}
