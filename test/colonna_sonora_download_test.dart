import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/features/musica/club_track.dart';

/// Il sito finto: serve [body] come mp3 (o [status] / una pagina, per gli errori)
/// e conta le richieste.
class _Site {
  late HttpServer server;
  var body = List<int>.generate(300000, (i) => i % 251);
  var status = HttpStatus.ok;
  var html = false;
  var gets = 0;
  var heads = 0;

  Uri get url => Uri.parse(
    'http://${server.address.host}:${server.port}/audio/canzoni_autoprodotte.mp3',
  );

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      if (req.method == 'HEAD') {
        heads++;
      } else {
        gets++;
      }
      res.statusCode = status;
      res.headers.contentType = html
          ? ContentType.html
          : ContentType('audio', 'mpeg');
      res.contentLength = body.length;
      if (req.method != 'HEAD') res.add(body);
      await res.close();
    });
  }
}

void main() {
  // Le prove scaricano davvero, da un server sul computer.
  setUpAll(() => HttpOverrides.global = null);

  late _Site site;
  late Directory dir;

  setUp(() async {
    site = _Site();
    await site.start();
    dir = await Directory.systemTemp.createTemp('colonna_sonora');
  });

  tearDown(() async {
    await site.server.close(force: true);
    await dir.delete(recursive: true);
  });

  ClubTrackCache cache() =>
      ClubTrackCache(url: site.url, directory: () async => dir);

  List<String> files() =>
      [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();

  test('colonna sonora del club: si scarica una volta, con l\'avanzamento, e '
      'poi suona dal telefono', () async {
    final progress = <double>[];
    final path = await cache().path(onProgress: progress.add);
    expect(path, '${dir.path}/colonna_sonora_club_300000.mp3');
    expect(await File(path).readAsBytes(), site.body);
    expect(progress.first, 0);
    expect(progress.last, 1);
    expect(files(), ['colonna_sonora_club_300000.mp3']);
    expect(site.gets, 1);

    // All'apertura dopo: niente download, solo il controllo del peso sul sito.
    final again = cache();
    expect(await again.path(), path);
    await again.pendingUpdate;
    expect(site.gets, 1);
    expect(site.heads, 1);
    expect(files(), ['colonna_sonora_club_300000.mp3']);
  });

  test('colonna sonora del club: nuove canzoni sul sito arrivano da sole '
      "all'apertura successiva, senza aggiornare l'app", () async {
    final old = await cache().path();
    File(old).setLastModifiedSync(DateTime(2026));
    site.body = List<int>.generate(420000, (i) => (i * 7) % 253);

    // Questa volta suona ancora la vecchia, la nuova si scarica accanto.
    final now = cache();
    expect(await now.path(), old);
    await now.pendingUpdate;
    expect(files(), [
      'colonna_sonora_club_300000.mp3',
      'colonna_sonora_club_420000.mp3',
    ]);

    // Alla riapertura suona la nuova e la vecchia si cancella.
    final next = await cache().path();
    expect(next, '${dir.path}/colonna_sonora_club_420000.mp3');
    expect(await File(next).readAsBytes(), site.body);
    expect(files(), ['colonna_sonora_club_420000.mp3']);
  });

  test('colonna sonora del club: sito non raggiungibile o pagina al posto '
      'della musica, nessun file a metà sul telefono', () async {
    site.status = HttpStatus.notFound;
    await expectLater(cache().path(), throwsA(isA<HttpException>()));
    expect(files(), isEmpty);

    site
      ..status = HttpStatus.ok
      ..html = true;
    await expectLater(cache().path(), throwsA(isA<HttpException>()));
    expect(files(), isEmpty);

    final offline = cache();
    await site.server.close(force: true);
    await expectLater(offline.path(), throwsA(isA<SocketException>()));
    expect(files(), isEmpty);
  });
}
