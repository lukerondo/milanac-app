import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/private_data.dart';
import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/teams.dart';
import '../../shared/member_photo.dart';
import '../volto/face.dart';
import 'member.dart';

abstract class RosaRepository {
  Stream<List<Member>> watchAll();
  Future<void> save(Member member);
  Future<void> remove(String id);

  /// Aggiorna solo i campi della carta (anche il giocatore sul proprio profilo).
  Future<void> saveCard(Member member);

  /// Aggiorna i dati personali dalle Impostazioni (nome, gamertag, nascita...).
  Future<void> saveProfile(Member member);

  /// Carica la nuova foto del profilo (JPEG) e la imposta; restituisce il percorso.
  Future<String> uploadPhoto(Member member, Uint8List jpeg);
}

final rosaRepositoryProvider = Provider<RosaRepository>((ref) {
  if (AppConfig.isDemo) {
    // Come le regole di `profile_private`: i dati anagrafici degli altri li riceve
    // solo il Direttivo (vale anche per chi prova la demo da giocatore). Quando cambia
    // chi guarda (profilo arrivato, altro ruolo) la rosa si rilegge.
    final repo = DemoRosaRepository(
      viewer: () => ref.read(profileProvider).value,
    );
    ref.listen(profileProvider, (_, _) => repo.refresh());
    return repo;
  }
  return _SupabaseRosaRepository(ref);
});

final rosaProvider = StreamProvider<List<Member>>((ref) {
  // Al cambio di account si ricarica con i permessi del nuovo utente; anche quando
  // si entra o si esce dal Direttivo (i dati anagrafici degli altri li riceve solo lui).
  ref.watch(currentUserIdProvider);
  ref.watch(profileProvider.select((p) => p.value?.isDirettivo ?? false));
  return ref.watch(rosaRepositoryProvider).watchAll();
});

class _SupabaseRosaRepository implements RosaRepository {
  _SupabaseRosaRepository(this._ref);
  final Ref _ref;

  /// I profili con i dati anagrafici di `profile_private`: un giocatore riceve solo i
  /// propri, il Direttivo quelli di tutti (prima della migrazione 0025 arrivano ancora
  /// con le colonne di `profiles`).
  @override
  Stream<List<Member>> watchAll() {
    final client = _ref.read(supabaseProvider);
    final profiles = client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('joined_at', ascending: true);
    return combineLatest(
      profiles,
      watchPrivateRows(client),
      (rows, private) => [
        for (final r in rows)
          Member.fromMap(withPrivateRow(r, private[r['id']])),
      ],
    );
  }

  @override
  Future<void> save(Member m) async {
    // Nota: le query Supabase partono solo quando vengono attese (await).
    await _ref
        .read(supabaseProvider)
        .from('profiles')
        .update(m.toUpdateMap())
        .eq('id', m.id);
  }

  @override
  Future<void> saveCard(Member m) async {
    await _ref
        .read(supabaseProvider)
        .from('profiles')
        .update(m.cardMap())
        .eq('id', m.id);
  }

  @override
  Future<void> saveProfile(Member m) async {
    final client = _ref.read(supabaseProvider);
    var fields = m.personalMap();
    try {
      await savePrivateRow(client, m.id, m.privateMap());
    } catch (e) {
      if (!isMissingTable(e)) rethrow;
      // Database prima della migrazione 0025: i dati anagrafici stanno ancora in
      // profiles. Dopo, quelle colonne non ci sono più e lì non vanno mai mandati.
      fields = {...fields, ...m.privateMap()};
    }
    await client.from('profiles').update(fields).eq('id', m.id);
  }

  @override
  Future<String> uploadPhoto(Member m, Uint8List jpeg) async {
    final client = _ref.read(supabaseProvider);
    final path = '${m.id}/foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage
        .from(avatarsBucket)
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    await client.from('profiles').update({'avatar_path': path}).eq('id', m.id);
    if (m.avatarPath != null) {
      await client.storage.from(avatarsBucket).remove([m.avatarPath!]);
    }
    return path;
  }

  /// Rifiuta una richiesta di accesso: il profilo viene disattivato (resta in attesa).
  @override
  Future<void> remove(String id) async {
    await _ref
        .read(supabaseProvider)
        .from('profiles')
        .update({'active': false})
        .eq('id', id);
  }
}

/// Dati di esempio in memoria per la modalità demo e i test.
class DemoRosaRepository implements RosaRepository {
  DemoRosaRepository({this._viewer}) {
    _changes = StreamController<void>.broadcast(
      onListen: () => _changes.add(null),
    );
  }

  /// Chi guarda la rosa: come per `profile_private` sul server, i dati anagrafici degli
  /// altri arrivano solo al Direttivo. Senza, si vedono tutti (il Direttivo della demo).
  final Profile? Function()? _viewer;

  late final StreamController<void> _changes;

  final _members = <Member>[
    Member(
      id: 'demo',
      displayName: 'Demo Direttivo',
      firstName: 'Demo',
      lastName: 'Direttivo',
      birthYear: 1992,
      motto: 'Milano siamo noi!',
      gamertag: 'MILANAC_Demo',
      role: ClubRole.direttivo,
      direttivoRoles: const [DirettivoRole.capitano, DirettivoRole.gestore],
      fieldPosition: 'CC',
      shirtNumber: 10,
      joinedAt: DateTime(2025, 1, 10),
      overall: 82,
      face: const Face(skin: 2, hair: 3, hairColor: 0, brows: 1, beard: 2),
    ),
    Member(
      id: 'p2',
      displayName: 'Marco Rossi',
      firstName: 'Marco',
      lastName: 'Rossi',
      birthYear: 1998,
      motto: 'Prima il gol, poi tutto il resto.',
      gamertag: 'Diavolo_9',
      role: ClubRole.giocatore,
      fieldPosition: 'ATT',
      shirtNumber: 9,
      joinedAt: DateTime(2025, 2, 3),
      overall: 86,
      playStyle: 'Finalizzatore',
      platform: GamePlatform.ps5,
      face: const Face(
        skin: 1,
        hair: 2,
        hairColor: 1,
        eyeColor: 1,
        beard: 4,
        mouth: 2,
        accessory: 1,
      ),
    ),
    Member(
      id: 'p3',
      displayName: 'Luca Bianchi',
      firstName: 'Luca',
      lastName: 'Bianchi',
      birthYear: 1995,
      gamertag: 'Muro_Rossonero',
      role: ClubRole.giocatore,
      fieldPosition: 'DC',
      shirtNumber: 4,
      joinedAt: DateTime(2025, 3, 15),
      overall: 78,
      playStyle: 'Muro',
      platform: GamePlatform.ps5,
      face: const Face(
        skin: 3,
        hair: 0,
        hairColor: 0,
        eyes: 1,
        brows: 2,
        beard: 3,
        mouth: 1,
      ),
    ),
    Member(
      id: 'p4',
      displayName: 'Andrea Neri',
      firstName: 'Andrea',
      lastName: 'Neri',
      birthYear: 2001,
      gamertag: 'Saracinesca1',
      role: ClubRole.giocatore,
      fieldPosition: 'POR',
      shirtNumber: 1,
      joinedAt: DateTime(2025, 4, 20),
      overall: 70,
      teams: {Team.milanac, Team.futuro},
      face: const Face(
        skin: 0,
        hair: 4,
        hairColor: 3,
        eyes: 2,
        eyeColor: 2,
        accessory: 2,
      ),
    ),
    Member(
      id: 'p6',
      displayName: 'Paolo Verdi',
      firstName: 'Paolo',
      lastName: 'Verdi',
      birthYear: 2003,
      gamertag: 'Futuro_23',
      role: ClubRole.giocatore,
      fieldPosition: 'CC',
      shirtNumber: 23,
      joinedAt: DateTime(2025, 9, 1),
      overall: 62,
      teams: {Team.futuro},
      face: const Face(
        skin: 4,
        hair: 6,
        hairColor: 0,
        brows: 1,
        beard: 1,
        accessory: 3,
      ),
    ),
    // Rimosso dal Direttivo: compare solo in Rosa e squadre, tra i "Rimossi".
    Member(
      id: 'p7',
      displayName: 'Gigi Ferri',
      firstName: 'Luigi',
      lastName: 'Ferri',
      birthYear: 1999,
      gamertag: 'Ferri_7',
      role: ClubRole.giocatore,
      fieldPosition: 'ED',
      shirtNumber: 7,
      joinedAt: DateTime(2025, 6, 1),
      overall: 65,
      active: false,
      face: const Face(skin: 1, hair: 2, hairColor: 2, brows: 0, beard: 0),
    ),
  ];

  void _emit() => _changes.add(null);

  /// Chi guarda è cambiato: la rosa si rilegge con i suoi permessi.
  void refresh() => _emit();

  /// La rosa come la riceve chi guarda: i dati anagrafici solo i propri, tutti per il
  /// Direttivo (nessuno se non si sa ancora chi è).
  List<Member> _visible() {
    final viewer = _viewer;
    if (viewer == null) return List.of(_members);
    final me = viewer();
    bool canSee(Member m) => me != null && (me.isDirettivo || me.id == m.id);
    return [for (final m in _members) canSee(m) ? m : m.withoutPrivateData()];
  }

  @override
  Stream<List<Member>> watchAll() async* {
    yield _visible();
    yield* _changes.stream.map((_) => _visible());
  }

  /// Come l'update di `profiles`: i dati anagrafici (in `profile_private`) restano
  /// quelli salvati, anche se [m] arriva senza (vista di un giocatore).
  @override
  Future<void> save(Member m) async {
    final i = _members.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      final old = _members[i];
      _members[i] = m.copyWith(
        firstName: old.firstName,
        lastName: old.lastName,
        birthYear: old.birthYear,
        birthDate: old.birthDate,
      );
    }
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    _members.removeWhere((m) => m.id == id);
    _emit();
  }

  @override
  Future<void> saveCard(Member m) => save(m);

  /// Come `saveProfile` sul server: i dati anagrafici presenti in [m] sostituiscono
  /// quelli salvati, quelli che mancano restano.
  @override
  Future<void> saveProfile(Member m) async {
    final i = _members.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      final old = _members[i];
      _members[i] = m.copyWith(
        firstName: m.firstName ?? old.firstName,
        lastName: m.lastName ?? old.lastName,
        birthYear: m.birthYear ?? old.birthYear,
        birthDate: m.birthDate ?? old.birthDate,
      );
    }
    _emit();
  }

  @override
  Future<String> uploadPhoto(Member m, Uint8List jpeg) async {
    final path = '${m.id}/foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    demoPhotos[path] = jpeg;
    final i = _members.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      final old = _members[i];
      _members[i] = old.withPersonalData(
        displayName: old.displayName,
        gamertag: old.gamertag,
        birthDate: old.birthDate,
        city: old.city,
        nationality: old.nationality,
        preferredFoot: old.preferredFoot,
        avatarPath: path,
      );
    }
    _emit();
    return path;
  }
}
