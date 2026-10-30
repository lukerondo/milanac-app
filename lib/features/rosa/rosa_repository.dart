import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/private_data.dart';
import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import '../../shared/member_photo.dart';
import 'member.dart';

abstract class RosaRepository {
  Stream<List<Member>> watchAll();
  Future<void> save(Member member);
  Future<void> remove(String id);

  /// Aggiorna solo i campi della carta (anche il giocatore sul proprio profilo).
  Future<void> saveCard(Member member);

  /// Colonne della carta che il server non ha ancora (PlayStyle della 0028, statistiche
  /// FUT della 0032): le carte si salvano senza. Si riempie al primo salvataggio
  /// rifiutato per questo.
  Set<String> get missingColumns;

  /// Aggiorna i dati personali dalle Impostazioni (nome, gamertag, nascita...).
  Future<void> saveProfile(Member member);

  /// Carica la nuova foto del profilo di [memberId] (il JPEG inquadrato, 720×900) al
  /// posto di [previous] e restituisce il percorso. Funziona anche durante la
  /// registrazione: ognuno scrive solo nella propria cartella del bucket.
  Future<String> uploadPhoto(
    String memberId,
    Uint8List jpeg, {
    String? previous,
  });

  /// Elimina definitivamente l'account di un altro membro (solo Direttivo).
  Future<void> deleteAccount(String id);

  /// Toglie la foto del profilo di un membro (moderazione del Direttivo).
  Future<void> removePhoto(Member member);
}

/// Colonne di `profiles` arrivate con le migrazioni più recenti: un server non ancora
/// aggiornato non le ha.
const recentProfileColumns = ['play_styles', 'fut_stats'];

/// Aggiorna un profilo con [update]. Se al database manca una delle colonne recenti
/// (PostgREST risponde PGRST204 nominandola) si riscrive senza e il resto si salva;
/// quelle in [skip] non si mandano nemmeno. Restituisce le colonne che mancano.
Future<Set<String>> updateWithoutMissing(
  Map<String, dynamic> fields,
  Future<void> Function(Map<String, dynamic> fields) update, {
  Set<String> skip = const {},
}) async {
  final missing = {...skip.where(fields.containsKey)};
  final send = {...fields}..removeWhere((k, _) => skip.contains(k));
  while (true) {
    try {
      await update(send);
      return missing;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST204') rethrow;
      final column = recentProfileColumns
          .where((c) => send.containsKey(c) && e.message.contains("'$c'"))
          .firstOrNull;
      if (column == null) rethrow;
      send.remove(column);
      missing.add(column);
    }
  }
}

/// Una funzione nuova del database non c'è ancora (migrazione non applicata).
const serverNotUpdated =
    'Per ora non si può: il server del club non è ancora aggiornato.';

/// Il club ha sempre almeno un membro del Direttivo attivo (come sul server).
const lastDirettivoMessage =
    'Il club deve avere almeno un membro del Direttivo: nominane prima un altro';

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
  // Le foto dell'account precedente non restano sul telefono.
  PhotoDiskCache.forUser(ref.watch(currentUserIdProvider));
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
    return combineLatest(profiles, watchPrivateRows(client), (rows, private) {
      final members = [
        for (final r in rows)
          Member.fromMap(withPrivateRow(r, private[r['id']])),
      ];
      // Sul telefono restano solo le foto attuali dei membri.
      PhotoDiskCache.syncWithRoster(members.map((m) => m.avatarPath));
      return members;
    });
  }

  @override
  Future<void> save(Member m) => _update(m.id, m.toUpdateMap());

  @override
  Future<void> saveCard(Member m) => _update(m.id, m.cardMap());

  /// Le colonne mancanti all'ultimo salvataggio: si riprova sempre con tutte, così
  /// appena il server è aggiornato (migrazione applicata) si salvano anche quelle.
  @override
  var missingColumns = <String>{};

  Future<void> _update(String id, Map<String, dynamic> fields) async {
    // Nota: le query Supabase partono solo quando vengono attese (await).
    final profiles = _ref.read(supabaseProvider).from('profiles');
    missingColumns = await updateWithoutMissing(
      fields,
      (f) => profiles.update(f).eq('id', id),
    );
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
  Future<String> uploadPhoto(
    String memberId,
    Uint8List jpeg, {
    String? previous,
  }) async {
    final client = _ref.read(supabaseProvider);
    final path = '$memberId/foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage
        .from(avatarsBucket)
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    // Si vede subito (anche nel walkout) senza riscaricarla.
    rememberPhoto(path, jpeg);
    try {
      // Il volto disegnato si toglie: anche le app vecchie mostrano la foto.
      await client
          .from('profiles')
          .update({'avatar_path': path, 'face': null})
          .eq('id', memberId);
    } catch (e) {
      // Senza risposta (rete persa) il profilo potrebbe essere già aggiornato: si
      // controlla. Il file si cancella solo se di sicuro il profilo non lo usa: meglio
      // un file in più nel bucket che una carta che punta a una foto cancellata.
      final saved = e is PostgrestException
          ? null
          : await _savedAvatar(memberId);
      if (saved?.path != path) {
        localPhotos.remove(path);
        if (e is PostgrestException || saved != null) {
          try {
            await client.storage.from(avatarsBucket).remove([path]);
          } catch (_) {}
        }
        rethrow;
      }
    }
    await PhotoDiskCache.write(path, jpeg);
    if (previous != null) {
      // La foto nuova è già al suo posto: se la vecchia non si cancella, pazienza.
      try {
        await client.storage.from(avatarsBucket).remove([previous]);
      } catch (_) {}
    }
    return path;
  }

  /// La foto a cui punta ora il profilo; null se non si riesce a saperlo.
  Future<({String? path})?> _savedAvatar(String memberId) async {
    try {
      final row = await _ref
          .read(supabaseProvider)
          .from('profiles')
          .select('avatar_path')
          .eq('id', memberId)
          .single();
      return (path: row['avatar_path'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Elimina l'account di un membro con `delete_member_account` (migrazione 0026).
  @override
  Future<void> deleteAccount(String id) async {
    try {
      await _ref
          .read(supabaseProvider)
          .rpc('delete_member_account', params: {'p_member': id});
    } catch (e) {
      if (isMissingFunction(e)) throw const AppError(serverNotUpdated);
      rethrow;
    }
  }

  /// Prima il riferimento nel profilo, poi il file: se lo Storage non lo permette
  /// ancora (migrazione 0026 non applicata) il file resta, ma non si vede più.
  @override
  Future<void> removePhoto(Member m) async {
    final client = _ref.read(supabaseProvider);
    final path = m.avatarPath;
    await client.from('profiles').update({'avatar_path': null}).eq('id', m.id);
    if (path == null) return;
    await PhotoDiskCache.delete(path);
    try {
      await client.storage.from(avatarsBucket).remove([path]);
    } catch (_) {}
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
      playStyles: const [
        'tiro_potente+',
        'colpo_di_testa+',
        'scatto',
        'primo_controllo',
      ],
      platform: GamePlatform.ps5,
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
    ),
  ];

  void _emit() => _changes.add(null);

  /// Chi guarda è cambiato: la rosa si rilegge con i suoi permessi.
  void refresh() => _emit();

  /// Aggiunge un membro (per i test: per esempio chi si è appena registrato).
  void add(Member m) {
    _members.add(m);
    _emit();
  }

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
  /// quelli salvati, anche se [m] arriva senza (vista di un giocatore); come il
  /// trigger `direttivo_guard`, retrocedendo le etichette si azzerano e l'ultimo
  /// membro attivo del Direttivo non si retrocede né si rimuove.
  @override
  Future<void> save(Member m) async {
    final i = _members.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      final old = _members[i];
      bool leading(Member x) => x.role == ClubRole.direttivo && x.active;
      if (leading(old) &&
          !leading(m) &&
          !_members.any((x) => x.id != m.id && leading(x))) {
        throw const AppError(lastDirettivoMessage);
      }
      _members[i] = m.copyWith(
        firstName: old.firstName,
        lastName: old.lastName,
        birthYear: old.birthYear,
        birthDate: old.birthDate,
        direttivoRoles: m.role == ClubRole.direttivo ? null : const [],
      );
    }
    _emit();
  }

  @override
  Future<void> deleteAccount(String id) async {
    final me = _viewer?.call();
    if (me?.id == id) {
      throw const AppError(
        'Il tuo account si elimina da Impostazioni → Account',
      );
    }
    if (me != null && !me.isDirettivo) {
      throw const AppError(
        'Solo il Direttivo può eliminare l\'account di un membro',
      );
    }
    _members.removeWhere((m) => m.id == id);
    _emit();
  }

  @override
  Future<void> removePhoto(Member m) async {
    final i = _members.indexWhere((x) => x.id == m.id);
    if (i < 0) return;
    localPhotos.remove(_members[i].avatarPath);
    _members[i] = _members[i].copyWith(avatarPath: null);
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    _members.removeWhere((m) => m.id == id);
    _emit();
  }

  @override
  Future<void> saveCard(Member m) => save(m);

  @override
  Set<String> get missingColumns => const {};

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
  Future<String> uploadPhoto(
    String memberId,
    Uint8List jpeg, {
    String? previous,
  }) async {
    final path = '$memberId/foto_${DateTime.now().microsecondsSinceEpoch}.jpg';
    rememberPhoto(path, jpeg);
    if (previous != null) localPhotos.remove(previous);
    final i = _members.indexWhere((x) => x.id == memberId);
    if (i >= 0) _members[i] = _members[i].copyWith(avatarPath: path);
    _emit();
    return path;
  }
}
