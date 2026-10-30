import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/features/carta/fut_card.dart';
import 'package:milanac/features/carta/fut_stats.dart';
import 'package:milanac/features/foto/photo_frame.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/member_photo.dart';
import 'package:milanac/shared/silhouette.dart';

import 'helpers.dart';

/// Una "foto" vera (PNG) di [w]×[h], rossa sopra e nera sotto.
Uint8List _photo(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = p.y < h / 2 ? 200 : 10
      ..g = 20
      ..b = 30;
  }
  return img.encodePng(image);
}

Member _keeper({FutStats stats = FutStats.empty, String? avatarPath}) => Member(
  id: 'immu',
  displayName: 'Immu',
  role: ClubRole.giocatore,
  joinedAt: DateTime(2025, 9, 1),
  fieldPosition: 'POR',
  shirtNumber: 1,
  overall: 77,
  futStats: stats,
  avatarPath: avatarPath,
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  tearDown(localPhotos.clear);

  group('Statistiche FUT', () {
    test('sigle italiane: di movimento e da portiere', () {
      expect(FutStat.forPosition('ATT').map((s) => s.short), [
        'VEL',
        'TIR',
        'PAS',
        'DRI',
        'DIF',
        'FIS',
      ]);
      expect(FutStat.forPosition('POR').map((s) => s.short), [
        'TUF',
        'PRE',
        'RIN',
        'RIF',
        'VEL',
        'PIA',
      ]);
      expect(FutStat.forPosition(null), FutStat.outfield);
    });

    test('lette senza fidarsi, salvate con le chiavi del database', () {
      final s = FutStats.fromJson({
        'pac': 91,
        'sho': 84.0,
        'div': 70,
        'vel': 80, // chiave sconosciuta
        'pas': 0, // fuori da 1–99
        'dri': 100,
        'def': 75.5, // non intero
        'phy': '72', // non un numero
      });
      expect(s[FutStat.velocita], 91);
      expect(s[FutStat.tiro], 84);
      expect(s[FutStat.tuffo], 70);
      expect(s[FutStat.passaggio], isNull);
      expect(s.toJson(), {'pac': 91, 'sho': 84, 'div': 70});
      expect(FutStats.fromJson(null), FutStats.empty);
      expect(FutStats.fromJson([1, 2]), FutStats.empty);
    });

    test('cambiando ruolo restano entrambe; i valori stanno tra 1 e 99', () {
      var s = FutStats.empty
          .withValue(FutStat.velocita, 120)
          .withValue(FutStat.tuffo, 0)
          .withValue(FutStat.riflessi, 88);
      expect(s[FutStat.velocita], 99);
      expect(s[FutStat.tuffo], 1);
      expect(s.hasAnyFor('POR'), isTrue);
      expect(s.hasAnyFor('ATT'), isTrue);
      s = s.withValue(FutStat.velocita, null);
      expect(s.hasAnyFor('ATT'), isFalse);
      expect(s, FutStats.fromJson(s.toJson()));
    });

    test(
      'il profilo le legge (anche senza la colonna, server non aggiornato)',
      () {
        Map<String, dynamic> row([Object? stats]) => {
          'id': 'x',
          'display_name': 'Fabio',
          'joined_at': '2025-09-01',
          'fut_stats': ?stats,
        };
        expect(Member.fromMap(row({'pac': 90})).futStats[FutStat.velocita], 90);
        expect(Member.fromMap(row()).futStats, FutStats.empty);
        expect(Member.fromMap(row({'pac': 90})).cardMap()['fut_stats'], {
          'pac': 90,
        });
      },
    );
  });

  group('Inquadratura della foto', () {
    const frame = Size(200, 250);

    test(
      'all\'inizio copre il riquadro, centrata, con la parte alta in vista',
      () {
        final f = PhotoFraming.initial(const Size(1000, 2000), frame);
        expect(f.scale, .2); // la larghezza comanda
        expect(f.offset.dx, 0);
        expect(f.offset.dy, closeTo((250 - 400) * .3, 1e-9));
        final src = f.source(frame);
        expect(src.width, closeTo(1000, 1e-9));
        expect(src.height, closeTo(1250, 1e-9));
        expect(src.width / src.height, closeTo(cardPhotoAspect, 1e-9));
      },
    );

    test(
      'mai spazi vuoti: niente zoom sotto la copertura né fuori dai bordi',
      () {
        const image = Size(800, 800);
        final f = const PhotoFraming(
          .01,
          Offset(500, -900),
        ).clamped(image, frame);
        expect(f.scale, PhotoFraming.coverScale(image, frame));
        expect(f.offset.dx, lessThanOrEqualTo(0));
        expect(f.offset.dy, greaterThanOrEqualTo(250 - 800 * f.scale));
        final src = f.source(frame);
        expect(src.left, greaterThanOrEqualTo(0));
        expect(src.top, greaterThanOrEqualTo(0));
        expect(src.right, lessThanOrEqualTo(800.0001));
        expect(src.bottom, lessThanOrEqualTo(800.0001));
      },
    );

    test('allargando con due dita il punto sotto le dita resta fermo', () {
      const image = Size(1000, 1250);
      final start = PhotoFraming.initial(image, frame);
      const focal = Offset(120, 90);
      final pointBefore = (focal - start.offset) / start.scale;
      final zoomed = PhotoFraming.zoom(start, 2, focal, focal, image, frame);
      expect(zoomed.scale, closeTo(start.scale * 2, 1e-9));
      final pointAfter = (focal - zoomed.offset) / zoomed.scale;
      expect(pointAfter.dx, closeTo(pointBefore.dx, 1e-6));
      expect(pointAfter.dy, closeTo(pointBefore.dy, 1e-6));
      // Al massimo 5 volte.
      final far = PhotoFraming.zoom(start, 50, focal, focal, image, frame);
      expect(far.scale, closeTo(start.scale * 5, 1e-9));
    });

    test('misure qualsiasi (telefoni e foto veri): l\'inquadratura si apre sempre', () {
      // Con la scala minima l'arrotondamento può lasciare la foto un'inezia più
      // piccola del riquadro: non deve mai rompere i limiti.
      for (final (image, frame) in [
        (const Size(1125, 2000), const Size(356, 445)),
        (const Size(1080, 1350), const Size(334, 417.5)),
        (const Size(2000, 1500), const Size(319, 398.75)),
        (const Size(1170, 2532), const Size(319, 398.75)),
      ]) {
        final f = PhotoFraming.initial(image, frame);
        final src = f.source(frame);
        expect(src.left, greaterThanOrEqualTo(-1e-6));
        expect(src.top, greaterThanOrEqualTo(-1e-6));
        expect(src.right, lessThanOrEqualTo(image.width + 1e-6));
        expect(src.bottom, lessThanOrEqualTo(image.height + 1e-6));
        // Anche lo zoom fino al minimo.
        PhotoFraming.zoom(f, .1, Offset.zero, Offset.zero, image, frame);
      }
      for (var w = 300.0; w <= 440; w += 1.5) {
        for (final long in [1500.0, 2000.0, 2532.0]) {
          for (final ratio in [3 / 4, 4 / 5, 9 / 16, 1.0, 4 / 3, 16 / 9]) {
            final image = Size(
              long * ratio.clamp(0, 1),
              long / ratio.clamp(1, 9),
            );
            PhotoFraming.initial(image, Size(w, w * 5 / 4));
          }
        }
      }
    });

    test('il ritaglio diventa un JPEG 720×900', () async {
      final codec = await ui.instantiateImageCodec(_photo(400, 600));
      final image = (await codec.getNextFrame()).image;
      final f = PhotoFraming.initial(const Size(400, 600), frame);
      final jpeg = await cropToJpeg(image, f.source(frame));
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, 720);
      expect(decoded.height, 900);
      // In alto il rosso della foto, in basso il nero.
      expect(decoded.getPixel(360, 60).r, greaterThan(150));
      expect(decoded.getPixel(360, 880).r, lessThan(60));
    });
  });

  group('La carta', () {
    Future<void> pumpCard(WidgetTester tester, Member m, {int bonus = 0}) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 210,
                  child: FutCard(member: m, bonus: bonus),
                ),
              ),
            ),
          ),
        );

    testWidgets('portiere: le sei statistiche da portiere, con il bonus; senza '
        'foto la sagoma', (tester) async {
      final stats = FutStats.empty
          .withValue(FutStat.tuffo, 80)
          .withValue(FutStat.presa, 76)
          .withValue(FutStat.velocita, 50); // di movimento: non si vede
      await pumpCard(tester, _keeper(stats: stats), bonus: 3);
      for (final label in ['TUF', 'PRE', 'RIN', 'RIF', 'VEL', 'PIA']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in ['TIR', 'PAS', 'DRI', 'DIF', 'FIS']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('83'), findsOneWidget); // TUF 80 + 3
      expect(find.text('79'), findsOneWidget); // PRE 76 + 3
      expect(find.text('53'), findsNothing); // VEL di movimento
      expect(find.text('80'), findsOneWidget); // overall 77 + 3
      expect(find.text('–'), findsNWidgets(4));
      expect(find.byType(CustomPaint), findsWidgets);
      final label = tester.getSemantics(find.byType(FutCard));
      expect(label.label, contains('Tuffo 83'));
      expect(label.label, contains('senza foto'));
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SilhouettePainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets('con la foto caricata: la foto, mai un volto disegnato', (
      tester,
    ) async {
      localPhotos['immu/foto_1.jpg'] = _photo(72, 90);
      await pumpCard(tester, _keeper(avatarPath: 'immu/foto_1.jpg'));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image && (w.image is MemoryImage || w.image is ResizeImage),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SilhouettePainter,
        ),
        findsNothing,
      );
    });
  });

  testWidgets('La mia carta senza foto: "Carica la tua foto", galleria, '
      'inquadratura e la foto finisce sulla carta', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();

    // La galleria del telefono restituisce una foto vera.
    final dir = Directory.systemTemp.createTempSync('milanac_foto');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/io.png')..writeAsBytesSync(_photo(600, 800));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => file.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        null,
      ),
    );

    await goToSection(tester, 'La mia carta');
    Member me() =>
        container.read(rosaProvider).value!.firstWhere((m) => m.id == 'demo');
    expect(me().avatarPath, isNull);
    // Sulla carta e tra le azioni.
    expect(find.text('Carica la tua foto'), findsNWidgets(2));

    // Il file si legge e si decodifica davvero: fuori dal tempo finto dei test.
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    }

    // La foto da inquadrare, già decodificata, dentro la pagina.
    final framed = find.descendant(
      of: find.byType(PhotoFramePage),
      matching: find.byType(RawImage),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Carica la tua foto').first);
      await until(() => framed.evaluate().isNotEmpty);
    });
    await tester.pump();
    expect(find.text('INQUADRA LA FOTO'), findsOneWidget);
    expect(framed, findsOneWidget);

    // Due dita: si allarga, e la foto resta dentro il riquadro.
    final area = find.byKey(const ValueKey('inquadra-foto'));
    final center = tester.getCenter(area);
    final before = tester.getSize(framed);
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0));
    await a.moveTo(center - const Offset(80, 0));
    await b.moveTo(center + const Offset(80, 0));
    await a.up();
    await b.up();
    await tester.pump();
    expect(tester.getSize(framed).width, closeTo(before.width * 4, 4));
    final photoRect = tester.getRect(framed), frameRect = tester.getRect(area);
    expect(photoRect.left, lessThanOrEqualTo(frameRect.left + .5));
    expect(photoRect.top, lessThanOrEqualTo(frameRect.top + .5));
    expect(photoRect.right, greaterThanOrEqualTo(frameRect.right - .5));
    expect(photoRect.bottom, greaterThanOrEqualTo(frameRect.bottom - .5));

    // "Indietro" mentre prepara la foto non chiude niente (né lei né la pagina sotto).
    await tester.runAsync(() async {
      await tester.tap(find.text('Usa questa foto'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await until(() => me().avatarPath != null);
    });
    await tester.pumpAndSettle();
    final path = me().avatarPath;
    expect(path, startsWith('demo/foto_'));
    expect(img.decodeJpg(localPhotos[path]!)!.width, 720);
    expect(find.text('INQUADRA LA FOTO'), findsNothing);
    expect(find.textContaining('Foto aggiornata'), findsOneWidget);
    // Ora c'è la foto, sulla carta al posto della sagoma: niente più invito, l'azione
    // diventa "Cambia la foto".
    expect(
      find.descendant(
        of: find.byType(FutCard),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image && (w.image is MemoryImage || w.image is ResizeImage),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FutCard),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SilhouettePainter,
        ),
      ),
      findsNothing,
    );
    expect(find.text('Carica la tua foto'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Cambia la foto'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cambia la foto'), findsOneWidget);
  });

  testWidgets('La carta di un compagno senza foto: sagoma, nessun invito', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    await goToSection(tester, 'Rosa completa');
    await tester.tap(find.text('MARCO ROSSI').first);
    await tester.pumpAndSettle();
    expect(find.byType(FutCard), findsOneWidget);
    expect(find.text('Carica la tua foto'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FutCard),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SilhouettePainter,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('se mentre prepara la foto si apre qualcosa sopra (il walkout), '
      'la foto arriva lo stesso e la pagina si chiude', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    Uint8List? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Scaffold()),
    );
    unawaited(
      nav.currentState!
          .push<Uint8List>(
            MaterialPageRoute(
              builder: (_) => PhotoFramePage(bytes: _photo(600, 800)),
            ),
          )
          .then((r) {
            result = r;
            done = true;
          }),
    );
    final framed = find.descendant(
      of: find.byType(PhotoFramePage),
      matching: find.byType(RawImage),
    );
    await tester.runAsync(() async {
      await tester.pump();
      for (var i = 0; i < 200 && framed.evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
      await tester.tap(find.text('Usa questa foto'));
      await tester.pump();
      // Il walkout di una carta speciale si apre sopra.
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('WALKOUT')),
          ),
        ),
      );
      for (var i = 0; i < 200 && !done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(img.decodeJpg(result!)!.width, 720);
    // Il walkout resta aperto; sotto, la pagina della foto non c'è più.
    expect(find.text('WALKOUT'), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoFramePage), findsNothing);
  });

  group('Copia delle foto sul telefono', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('milanac_cache');
      PhotoDiskCache.directory = () async => dir;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Uint8List jpeg() => img.encodeJpg(img.Image(width: 8, height: 10));

    test('si legge solo se intera; un file scritto a metà si butta', () async {
      final bytes = jpeg();
      await PhotoDiskCache.write('a/foto_1.jpg', bytes);
      expect(await PhotoDiskCache.read('a/foto_1.jpg'), bytes);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), [
        'a_foto_1.jpg',
      ]);
      File('${dir.path}/a_foto_2.jpg')
          .writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      expect(await PhotoDiskCache.read('a/foto_2.jpg'), isNull);
      expect(File('${dir.path}/a_foto_2.jpg').existsSync(), isFalse);
    });

    test('la foto nuova toglie la vecchia; restano solo le foto della rosa; '
        'all\'uscita sparisce tutto', () async {
      await PhotoDiskCache.write('a/foto_1.jpg', jpeg());
      await PhotoDiskCache.write('b/foto_1.jpg', jpeg());
      await PhotoDiskCache.write('a/foto_2.jpg', jpeg());
      List<String> names() =>
          [for (final e in dir.listSync()) e.uri.pathSegments.last]..sort();
      expect(names(), ['a_foto_2.jpg', 'b_foto_1.jpg']);
      // b ha tolto la foto (o ha lasciato il club).
      await PhotoDiskCache.keepOnly({'a/foto_2.jpg'});
      expect(names(), ['a_foto_2.jpg']);
      await PhotoDiskCache.delete('a/foto_2.jpg');
      expect(names(), isEmpty);
      await PhotoDiskCache.write('c/foto_1.jpg', jpeg());
      await PhotoDiskCache.clear();
      expect(dir.existsSync(), isFalse);
      dir.createSync();
    });

    test('una foto appena arrivata resta anche se la rosa non la ha ancora; '
        'la pulizia non tocca le foto che si stanno scrivendo', () async {
      List<String> names() =>
          [for (final e in dir.listSync()) e.uri.pathSegments.last]..sort();
      final bytes = jpeg();
      rememberPhoto('d/foto_1.jpg', bytes);
      await PhotoDiskCache.write('d/foto_1.jpg', bytes);
      await PhotoDiskCache.write('e/foto_1.jpg', bytes);
      await PhotoDiskCache.keepOnly({});
      expect(names(), ['d_foto_1.jpg']);
      // La rosa cambia proprio mentre si salva la foto nuova: resta sul telefono.
      for (var i = 0; i < 40; i++) {
        final path = 'f/foto_$i.jpg';
        await Future.wait([
          PhotoDiskCache.write(path, bytes),
          PhotoDiskCache.keepOnly({path}),
          PhotoDiskCache.keepOnly({path}),
        ]);
        expect(await PhotoDiskCache.read(path), bytes, reason: path);
      }
      await PhotoDiskCache.clear();
      dir.createSync();
    });
  });

  testWidgets(
    'Con il testo grande del telefono la carta non cambia: overall su '
    'una riga, niente sopra la foto',
    (tester) async {
      Future<double> overallHeight(double scale) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: 210,
                    child: FutCard(
                      member: _keeper().copyWith(overall: 86),
                      bonus: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.text('86')).height;
      }

      final normal = await overallHeight(1);
      expect(await overallHeight(1.3), normal);
      expect(await overallHeight(2), normal);
    },
  );

  testWidgets('Impostazioni: la tua foto si toglie (sulla carta torna la '
      'sagoma)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    final repo = container.read(rosaRepositoryProvider);
    final path = await repo.uploadPhoto('demo', _photo(72, 90));
    await tester.pumpAndSettle();
    Member me() =>
        container.read(rosaProvider).value!.firstWhere((m) => m.id == 'demo');
    expect(me().avatarPath, path);

    await goToSection(tester, 'Impostazioni');
    expect(find.text('Non ancora caricata'), findsNothing);
    await tester.tap(find.text('La tua foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Togli la foto'));
    await tester.pumpAndSettle();
    expect(find.text('Foto tolta.'), findsOneWidget);
    expect(me().avatarPath, isNull);
    expect(localPhotos[path], isNull);
    expect(find.text('Non ancora caricata'), findsOneWidget);
  });

  testWidgets('Registrazione, passo 3: la foto dalla galleria, inquadrata e '
      'caricata subito', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    // La pagina di registrazione non guarda la rosa: la si tiene attiva per leggerla.
    final roster = container.listen(rosaProvider, (_, _) {});
    addTearDown(roster.close);
    final dir = Directory.systemTemp.createTempSync('milanac_reg');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/io.png')
      ..writeAsBytesSync(_photo(900, 1200));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => file.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        null,
      ),
    );
    await goToPath(tester, '/registrazione?passo=3');
    expect(find.text('LA TUA FOTO'), findsOneWidget);
    expect(find.text('Scegli dalla galleria'), findsOneWidget);

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    }

    final framed = find.descendant(
      of: find.byType(PhotoFramePage),
      matching: find.byType(RawImage),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('scegli-foto')));
      await until(() => framed.evaluate().isNotEmpty);
    });
    await tester.pump();
    String? path() => container
        .read(rosaProvider)
        .value!
        .firstWhere((m) => m.id == 'demo')
        .avatarPath;
    await tester.runAsync(() async {
      await tester.tap(find.text('Usa questa foto'));
      await until(() => path() != null);
    });
    await tester.pumpAndSettle();
    expect(path(), startsWith('demo/foto_'));
    expect(find.text('Cambia foto'), findsOneWidget);
    expect(find.text('Passo 3 di 3'), findsOneWidget);
  });
}
