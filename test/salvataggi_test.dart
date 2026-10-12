import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/errors.dart';
import 'package:milanac/features/albo_doro/trophies_repository.dart';
import 'package:milanac/features/albo_doro/trophy.dart';
import 'package:milanac/features/formazione/formation_repository.dart';
import 'package:milanac/features/formazione/modules.dart';
import 'package:milanac/features/risultati/matches_repository.dart';
import 'package:milanac/features/tornei/tournaments_repository.dart';
import 'package:milanac/shared/club_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un Supabase finto in locale: registra le richieste ("POST /rest/v1/rpc/...") e
/// risponde come dice il test (di base 200 e un elenco vuoto).
class _FakeSupabase {
  late final HttpServer _server;
  late final SupabaseClient client;

  /// Le richieste nell'ordine in cui arrivano.
  final requests = <String>[];

  /// Il corpo JSON dell'ultima richiesta per ciascuna chiave.
  final bodies = <String, Object?>{};

  /// Risposte per "METODO /percorso": stato e corpo JSON (null = nessun corpo).
  final responses = <String, (int, Object?)>{};

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        [],
        (all, b) => all..addAll(b),
      );
      final key = '${request.method} ${request.uri.path}';
      requests.add(key);
      if (request.headers.contentType?.mimeType == 'application/json' &&
          bytes.isNotEmpty) {
        bodies[key] = jsonDecode(utf8.decode(bytes));
      }
      // Un file caricato: lo Storage risponde con la sua chiave.
      final upload =
          request.method == 'POST' &&
          request.uri.path.startsWith('/storage/v1/object/');
      final (status, json) =
          responses[key] ??
          (
            200,
            upload
                ? {
                    'Key': request.uri.path.substring(
                      '/storage/v1/object/'.length,
                    ),
                  }
                : const <Object>[],
          );
      request.response.statusCode = status;
      if (json != null) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(json));
      }
      await request.response.close();
    });
    client = SupabaseClient('http://127.0.0.1:${_server.port}', 'chiave');
  }

  Future<void> stop() async {
    await client.dispose();
    await _server.close(force: true);
  }

  /// Aspetta che arrivi la richiesta [key] (le pulizie dello Storage non si aspettano).
  Future<void> waitFor(String key) async {
    for (var i = 0; i < 200 && !requests.contains(key); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Un repository costruito con il client finto.
  T repository<T>(T Function(Ref ref) create) {
    final container = ProviderContainer(
      overrides: [supabaseProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    return container.read(Provider<T>(create));
  }
}

/// La risposta di PostgREST quando la funzione SQL non c'è ancora (migrazione non
/// applicata).
(int, Object?) _missingFunction(String name) => (
  404,
  {
    'code': 'PGRST202',
    'details': null,
    'hint': null,
    'message': 'Could not find the function public.$name in the schema cache',
  },
);

void main() {
  late _FakeSupabase server;

  setUp(() async {
    server = _FakeSupabase();
    await server.start();
  });
  tearDown(() => server.stop());

  group('contatti social', () {
    const links = [
      ClubLink(kind: LinkKind.instagram, url: 'https://instagram.com/milanac'),
      ClubLink(kind: LinkKind.sito, url: 'https://milanac.it'),
    ];

    test('tutto l\'elenco in una transazione (save_club_links)', () async {
      server.responses['POST /rest/v1/rpc/save_club_links'] = (204, null);
      await server.repository(SupabaseClubLinksRepository.new).saveAll(links);
      expect(server.requests, ['POST /rest/v1/rpc/save_club_links']);
      expect(server.bodies['POST /rest/v1/rpc/save_club_links'], {
        'p_links': [
          {'kind': 'instagram', 'url': 'https://instagram.com/milanac'},
          {'kind': 'sito', 'url': 'https://milanac.it'},
        ],
      });
    });

    test('senza save_club_links (database non aggiornato) si salva come '
        'prima', () async {
      server.responses
        ..['POST /rest/v1/rpc/save_club_links'] = _missingFunction(
          'save_club_links',
        )
        ..['POST /rest/v1/club_links'] = (
          201,
          [
            {'id': 'n1'},
            {'id': 'n2'},
          ],
        )
        ..['DELETE /rest/v1/club_links'] = (204, null);
      await server.repository(SupabaseClubLinksRepository.new).saveAll(links);
      expect(server.requests, [
        'POST /rest/v1/rpc/save_club_links',
        'POST /rest/v1/club_links',
        'DELETE /rest/v1/club_links',
      ]);
    });

    test('un altro errore non passa alla strada di prima', () async {
      server.responses['POST /rest/v1/rpc/save_club_links'] = (
        403,
        {'code': '42501', 'message': 'permission denied', 'details': null},
      );
      await expectLater(
        server.repository(SupabaseClubLinksRepository.new).saveAll(links),
        throwsA(isA<PostgrestException>()),
      );
      expect(server.requests, ['POST /rest/v1/rpc/save_club_links']);
    });
  });

  group('classifica', () {
    const rows = [
      StandingRow(teamName: 'Milan AC', won: 2, goalsFor: 5, isUs: true),
      StandingRow(teamName: 'Dinamo Pixel', lost: 2, goalsAgainst: 5),
    ];

    test('tutta la classifica in una transazione (save_standings)', () async {
      server.responses['POST /rest/v1/rpc/save_standings'] = (204, null);
      await server
          .repository(SupabaseTournamentsRepository.new)
          .saveStandings('tr1', rows);
      expect(server.requests, ['POST /rest/v1/rpc/save_standings']);
      final body = server.bodies['POST /rest/v1/rpc/save_standings']! as Map;
      expect(body['p_tournament'], 'tr1');
      expect(body['p_rows'], [
        {
          'team_name': 'Milan AC',
          'won': 2,
          'drawn': 0,
          'lost': 0,
          'goals_for': 5,
          'goals_against': 0,
          'is_us': true,
        },
        {
          'team_name': 'Dinamo Pixel',
          'won': 0,
          'drawn': 0,
          'lost': 2,
          'goals_for': 0,
          'goals_against': 5,
          'is_us': false,
        },
      ]);
    });

    test('senza save_standings si salva come prima', () async {
      server.responses
        ..['POST /rest/v1/rpc/save_standings'] = _missingFunction(
          'save_standings',
        )
        ..['POST /rest/v1/tournament_standings'] = (
          201,
          [
            {'id': 'r1'},
            {'id': 'r2'},
          ],
        )
        ..['DELETE /rest/v1/tournament_standings'] = (204, null);
      await server
          .repository(SupabaseTournamentsRepository.new)
          .saveStandings('tr1', rows);
      expect(server.requests, [
        'POST /rest/v1/rpc/save_standings',
        'POST /rest/v1/tournament_standings',
        'DELETE /rest/v1/tournament_standings',
      ]);
    });
  });

  group('pubblicazione della formazione', () {
    const formation = Formation(
      id: 'f1',
      module: '4-4-2',
      players: {0: 'p4', 9: 'p2'},
    );

    test('l\'ora della pubblicazione è quella del server', () async {
      server.responses['PATCH /rest/v1/formations'] = (
        200,
        [
          {'published_at': '2026-10-12T16:05:00+00:00'},
        ],
      );
      final published = await server
          .repository(SupabaseFormationRepository.new)
          .publish(formation);
      expect(published.publishedAt, DateTime.utc(2026, 10, 12, 16, 5));
      expect(published.publishedModule, '4-4-2');
      expect(published.publishedPlayers, {0: 'p4', 9: 'p2'});
      final sent = server.bodies['PATCH /rest/v1/formations']! as Map;
      expect(sent['published_players'], {'0': 'p4', '9': 'p2'});
    });

    test('nessuna riga cambiata: non risulta pubblicata', () async {
      server.responses['PATCH /rest/v1/formations'] = (200, const <Object>[]);
      await expectLater(
        server.repository(SupabaseFormationRepository.new).publish(formation),
        throwsA(
          isA<AppError>().having(
            (e) => e.message,
            'messaggio',
            contains('Formazione non trovata'),
          ),
        ),
      );
    });
  });

  group('prima il database, poi lo Storage', () {
    test('eliminare una partita: la riga, poi i suoi file', () async {
      server.responses
        ..['GET /rest/v1/match_media'] = (
          200,
          [
            {'storage_path': 'm1/clip.mp4'},
            {'storage_path': null},
          ],
        )
        ..['DELETE /rest/v1/matches'] = (204, null);
      await server.repository(SupabaseMatchesRepository.new).delete('m1');
      await server.waitFor('DELETE /storage/v1/object/match-media');
      expect(server.requests, [
        'GET /rest/v1/match_media',
        'DELETE /rest/v1/matches',
        'DELETE /storage/v1/object/match-media',
      ]);
      expect(server.bodies['DELETE /storage/v1/object/match-media'], {
        'prefixes': ['m1/clip.mp4'],
      });
    });

    test('se il database rifiuta, i file restano', () async {
      server.responses
        ..['GET /rest/v1/match_media'] = (
          200,
          [
            {'storage_path': 'm1/clip.mp4'},
          ],
        )
        ..['DELETE /rest/v1/matches'] = (
          403,
          {'code': '42501', 'message': 'permission denied', 'details': null},
        );
      await expectLater(
        server.repository(SupabaseMatchesRepository.new).delete('m1'),
        throwsA(isA<PostgrestException>()),
      );
      // Anche aspettando, nessun file tolto.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.requests, isNot(contains(startsWith('DELETE /storage'))));
    });

    test('un file che non si toglie non fa fallire l\'eliminazione', () async {
      server.responses
        ..['GET /rest/v1/match_media'] = (
          200,
          [
            {'storage_path': 'm1/clip.mp4'},
          ],
        )
        ..['DELETE /rest/v1/matches'] = (204, null)
        ..['DELETE /storage/v1/object/match-media'] = (
          500,
          {'statusCode': '500', 'error': 'boom', 'message': 'boom'},
        );
      await server.repository(SupabaseMatchesRepository.new).delete('m1');
      await server.waitFor('DELETE /storage/v1/object/match-media');
      expect(server.requests.last, 'DELETE /storage/v1/object/match-media');
    });

    test('foto del trofeo: la nuova, il trofeo, poi via la vecchia', () async {
      server.responses
        ..['PATCH /rest/v1/trophies'] = (204, null)
        ..['DELETE /storage/v1/object/trophies'] = (200, const <Object>[]);
      final trophy = Trophy(
        id: 't1',
        seasonId: 's25',
        name: 'Coppa FVPA',
        imagePath: 's25/vecchia.png',
      );
      await server
          .repository(SupabaseTrophiesRepository.new)
          .save(trophy, image: Uint8List.fromList([1, 2, 3]));
      expect(server.requests, hasLength(3));
      expect(
        server.requests[0],
        startsWith('POST /storage/v1/object/trophies/'),
      );
      expect(server.requests[1], 'PATCH /rest/v1/trophies');
      expect(server.requests[2], 'DELETE /storage/v1/object/trophies');
      expect(server.bodies['DELETE /storage/v1/object/trophies'], {
        'prefixes': ['s25/vecchia.png'],
      });
      // Il trofeo punta alla foto nuova.
      final saved = server.bodies['PATCH /rest/v1/trophies']! as Map;
      expect(saved['image_path'], startsWith('s25/'));
      expect(saved['image_path'], isNot('s25/vecchia.png'));
    });

    test('foto del trofeo rifiutata dal database: via la nuova, resta la '
        'vecchia', () async {
      server.responses['PATCH /rest/v1/trophies'] = (
        400,
        {
          'code': '23514',
          'message': 'violates check constraint',
          'details': null,
        },
      );
      final trophy = Trophy(
        id: 't1',
        seasonId: 's25',
        name: 'Coppa FVPA',
        imagePath: 's25/vecchia.png',
      );
      await expectLater(
        server
            .repository(SupabaseTrophiesRepository.new)
            .save(trophy, image: Uint8List.fromList([1, 2, 3])),
        throwsA(isA<PostgrestException>()),
      );
      final removed =
          server.bodies['DELETE /storage/v1/object/trophies']! as Map;
      expect(removed['prefixes'], [isNot('s25/vecchia.png')]);
    });

    test('eliminare un trofeo: la riga, poi la foto', () async {
      server.responses['DELETE /rest/v1/trophies'] = (204, null);
      await server
          .repository(SupabaseTrophiesRepository.new)
          .delete(
            Trophy(
              id: 't1',
              seasonId: 's25',
              name: 'Coppa FVPA',
              imagePath: 's25/coppa.png',
            ),
          );
      expect(server.requests, [
        'DELETE /rest/v1/trophies',
        'DELETE /storage/v1/object/trophies',
      ]);
    });

    test('foto del torneo sostituita: si toglie la vecchia solo a torneo '
        'aggiornato', () async {
      server.responses['PATCH /rest/v1/tournaments'] = (204, null);
      final path = await server
          .repository(SupabaseTournamentsRepository.new)
          .uploadImage(
            'tr1',
            Uint8List.fromList([1, 2, 3]),
            replacing: 'tr1/vecchia.jpg',
          );
      expect(path, startsWith('tr1/foto_'));
      expect(server.requests, [
        'POST /storage/v1/object/tournaments/$path',
        'PATCH /rest/v1/tournaments',
        'DELETE /storage/v1/object/tournaments',
      ]);
      expect(server.bodies['DELETE /storage/v1/object/tournaments'], {
        'prefixes': ['tr1/vecchia.jpg'],
      });
    });
  });
}
