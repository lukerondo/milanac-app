import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/private_data.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;

/// Un giocatore che prova l'app: Luca Bianchi della demo.
const _bianchi = Profile(
  id: 'p3',
  displayName: 'Luca Bianchi',
  role: ClubRole.giocatore,
  registrationCompleted: true,
  rulesAcceptedVersion: 1,
);

Member _member(List<Member> all, String id) =>
    all.firstWhere((m) => m.id == id);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('dati anagrafici in profile_private', () {
    test('la riga privata sostituisce solo nome, cognome e nascita', () {
      final profile = {
        'id': 'u1',
        'display_name': 'ROSSI',
        'first_name': 'Vecchio',
        'motto': 'Forza',
      };
      expect(withPrivateRow(profile, null), same(profile));
      final merged = withPrivateRow(profile, {
        'id': 'u1',
        'first_name': 'Marco',
        'last_name': 'Rossi',
        'birth_year': 1998,
        'updated_at': '2026-10-12T10:00:00Z',
      });
      expect(merged['first_name'], 'Marco');
      expect(merged['last_name'], 'Rossi');
      expect(merged['birth_year'], 1998);
      expect(merged['birth_date'], isNull);
      expect(merged['display_name'], 'ROSSI');
      expect(merged['motto'], 'Forza');
      expect(merged.containsKey('updated_at'), isFalse);

      final m = Member.fromMap({
        ...merged,
        'joined_at': '2025-02-03',
        'club_role': 'giocatore',
      });
      expect(m.fullName, 'Marco Rossi');
      expect(m.birthYear, 1998);
    });

    test('a profiles non vanno mai i dati anagrafici; in profile_private solo '
        'quelli presenti', () {
      final m = Member(
        id: 'u1',
        displayName: 'ROSSI',
        role: ClubRole.giocatore,
        joinedAt: DateTime(2025, 2, 3),
        firstName: 'Marco',
        lastName: 'Rossi',
        birthYear: 1998,
        birthDate: DateTime(1998, 5, 12),
        motto: 'Forza',
      );
      for (final map in [m.personalMap(), m.toUpdateMap(), m.cardMap()]) {
        for (final k in privateFields) {
          expect(map.containsKey(k), isFalse, reason: k);
        }
      }
      expect(m.personalMap()['motto'], 'Forza');
      expect(m.privateMap(), {
        'first_name': 'Marco',
        'last_name': 'Rossi',
        'birth_year': 1998,
        'birth_date': '1998-05-12',
      });
      // Chi non ha ricevuto i dati non li azzera.
      expect(m.withoutPrivateData().privateMap(), isEmpty);
      expect(m.withoutPrivateData().fullName, 'ROSSI');
    });

    test('lettura: tabella mancante o senza tempo reale non fermano la rosa, '
        'la rete sì (si riprova)', () async {
      final missing = StreamController<List<Map<String, dynamic>>>();
      final rows = privateRowsById(missing.stream);
      final got = <Object>[];
      final sub = rows.listen(got.add, onError: got.add);
      // Prima della migrazione 0025: nessuna riga, i dati restano quelli di profiles.
      missing.addError(
        const PostgrestException(
          message: 'Could not find the table',
          code: 'PGRST205',
        ),
      );
      await pumpEventQueue();
      expect(got, [<String, Map<String, dynamic>>{}]);
      await sub.cancel();

      final live = StreamController<List<Map<String, dynamic>>>();
      final events = <Object>[];
      final sub2 = privateRowsById(live.stream)
          .listen(events.add, onError: events.add);
      // Tempo reale non attivo: l'errore non passa, i dati letti sì.
      live.addError(
        const RealtimeSubscribeException(RealtimeSubscribeStatus.channelError),
      );
      live.add([
        {'id': 'p3', 'first_name': 'Luca'},
      ]);
      // Senza rete l'errore passa: chi ascolta riprova.
      live.addError(Exception('SocketException: Failed host lookup'));
      await pumpEventQueue();
      expect(events, hasLength(2));
      expect(events.first, {
        'p3': {'id': 'p3', 'first_name': 'Luca'},
      });
      expect(events.last.toString(), contains('SocketException'));
      await sub2.cancel();
      expect(
        isMissingTable(const PostgrestException(message: '', code: '42P01')),
        isTrue,
      );
      expect(
        isMissingTable(const PostgrestException(message: '', code: '42501')),
        isFalse,
      );
    });

    test(
      'profili e dati anagrafici insieme: si parte quando ci sono tutti e due, '
      'poi a ogni novità',
      () async {
        final profiles = StreamController<List<String>>();
        final private = StreamController<Map<String, String>>();
        final out = <String>[];
        final sub = combineLatest(
          profiles.stream,
          private.stream,
          (List<String> ids, Map<String, String> names) =>
              ids.map((id) => names[id] ?? id).join(','),
        ).listen(out.add);
        profiles.add(['a', 'b']);
        await pumpEventQueue();
        expect(out, isEmpty);
        private.add({'a': 'Anna'});
        await pumpEventQueue();
        expect(out, ['Anna,b']);
        profiles.add(['a', 'b', 'c']);
        await pumpEventQueue();
        expect(out.last, 'Anna,b,c');
        // La tabella che manca finisce dopo un valore: i profili continuano ad arrivare.
        private.add({'a': 'Anna', 'b': 'Bea'});
        await private.close();
        profiles.add(['b']);
        await pumpEventQueue();
        expect(out.last, 'Bea');
        await sub.cancel();
      },
    );
  });

  group('demo fedele: i dati degli altri solo al Direttivo', () {
    test(
      'un giocatore riceve solo i propri, il Direttivo quelli di tutti',
      () async {
        Profile? viewer = _bianchi;
        final repo = DemoRosaRepository(viewer: () => viewer);
        final asPlayer = await repo.watchAll().first;
        expect(_member(asPlayer, 'p3').fullName, 'Luca Bianchi');
        expect(_member(asPlayer, 'p3').birthYear, 1995);
        final rossi = _member(asPlayer, 'p2');
        expect(rossi.firstName, isNull);
        expect(rossi.lastName, isNull);
        expect(rossi.birthYear, isNull);
        expect(rossi.age, isNull);
        expect(_member(asPlayer, 'p7').fullName, 'Gigi Ferri');

        // Il giocatore salva la sua carta: i dati anagrafici di nessuno si perdono.
        await repo.saveCard(_member(asPlayer, 'p3').copyWith(shirtNumber: 5));
        // Il Direttivo salva un membro ricevuto senza dati anagrafici: restano.
        await repo.save(rossi.copyWith(overall: 87));

        viewer = Profile.demo;
        final asDirettivo = await repo.watchAll().first;
        expect(_member(asDirettivo, 'p2').fullName, 'Marco Rossi');
        expect(_member(asDirettivo, 'p2').overall, 87);
        expect(_member(asDirettivo, 'p3').shirtNumber, 5);
        expect(_member(asDirettivo, 'p3').birthYear, 1995);
        expect(_member(asDirettivo, 'p7').fullName, 'Luigi Ferri');

        // Nessuno collegato: niente dati anagrafici.
        viewer = null;
        final nobody = await repo.watchAll().first;
        expect(nobody.every((m) => m.firstName == null), isTrue);
      },
    );

    test('dalle Impostazioni: i dati anagrafici scritti cambiano, gli altri restano', () async {
      final repo = DemoRosaRepository(viewer: () => _bianchi);
      final me = _member(await repo.watchAll().first, 'p3');
      await repo.saveProfile(
        me.withPersonalData(
          displayName: 'BIANCHI',
          gamertag: me.gamertag,
          birthDate: null,
          city: 'Milano',
          nationality: 'IT',
          preferredFoot: PreferredFoot.destro,
          lastName: 'Bianchi Rossi',
        ),
      );
      final saved = _member(await repo.watchAll().first, 'p3');
      expect(saved.displayName, 'BIANCHI');
      expect(saved.firstName, 'Luca');
      expect(saved.lastName, 'Bianchi Rossi');
      expect(saved.birthYear, 1995);
      expect(saved.city, 'Milano');
    });
  });

  testWidgets('Rosa: un giocatore non trova nessuno cercando il nome vero, il '
      'Direttivo sì', (tester) async {
    Future<void> search(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    // Gigi Ferri (nome vero Luigi) torna in rosa.
    Future<void> reactivateFerri(ProviderContainer container) async {
      final all = await container.read(rosaProvider.future);
      await container
          .read(rosaRepositoryProvider)
          .save(_member(all, 'p7').copyWith(active: true));
      await tester.pumpAndSettle();
    }

    // Da giocatore.
    var container = await startAppAt(
      tester,
      todayInItalyAt(17),
      overrides: [
        profileProvider.overrideWith((ref) => Stream.value(_bianchi)),
      ],
    );
    await reactivateFerri(container);
    await goToSection(tester, 'Rosa completa');
    await search('gigi');
    expect(find.text('GIGI FERRI'), findsOneWidget);
    await search('luigi');
    expect(find.text('GIGI FERRI'), findsNothing);
    expect(find.text('Nessun membro corrisponde ai filtri.'), findsOneWidget);
    // Il cognome vero di un altro non porta a lui (Rossi: solo il nome sulla carta).
    final rossi = _member(container.read(rosaProvider).value!, 'p2');
    expect(rossi.fullName, 'Marco Rossi');
    expect(rossi.firstName, isNull);

    // Da Direttivo (la demo).
    await tester.pumpWidget(const SizedBox());
    container = await startAppAt(tester, todayInItalyAt(17));
    await reactivateFerri(container);
    await goToSection(tester, 'Rosa completa');
    await search('luigi');
    expect(find.text('GIGI FERRI'), findsOneWidget);
  });
}
