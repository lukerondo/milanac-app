import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/pages_repository.dart';
import 'package:milanac/features/regolamento/regolamento_2026.dart';
import 'package:milanac/features/regolamento/rules_editor_page.dart';
import 'package:milanac/features/regolamento/rules_reader.dart';
import 'package:milanac/features/regolamento/rules_repository.dart';
import 'package:milanac/main.dart';

/// Regolamento ufficiale 2026: grassetto nel testo, testi uguali alla migrazione 0033,
/// lettura e editor su telefoni stretti (320 e 360 dp), in chiaro e in scuro.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('it');
    // Caratteri veri (Barlow per il testo, Oswald per i titoli): le misure sono quelle
    // del telefono.
    for (final (family, weights) in [
      (bodyFont, ['400', '500', '600', '700']),
      (sportFont, ['400', '500', '600', '700']),
    ]) {
      final loader = FontLoader(family);
      for (final w in weights) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
      }
      await loader.load();
    }
  });

  group('Grassetto con **testo**', () {
    test('i pezzi in grassetto e quelli normali, nell\'ordine', () {
      expect(boldSegments('Prima **forte** poi'), [
        (text: 'Prima ', bold: false),
        (text: 'forte', bold: true),
        (text: ' poi', bold: false),
      ]);
      expect(boldSegments('**Sanzioni:** si va **fuori**'), [
        (text: 'Sanzioni:', bold: true),
        (text: ' si va ', bold: false),
        (text: 'fuori', bold: true),
      ]);
      expect(boldSegments('Senza niente'), [
        (text: 'Senza niente', bold: false),
      ]);
    });

    test('un ** senza il suo compagno resta com\'è', () {
      expect(boldSegments('Finisce 3 ** 2'), [
        (text: 'Finisce 3 ** 2', bold: false),
      ]);
      expect(boldSegments('**sì** e **no'), [
        (text: 'sì', bold: true),
        (text: ' e **no', bold: false),
      ]);
      expect(boldSegments('****'), [(text: '****', bold: false)]);
      // Il grassetto non attraversa le righe.
      expect(boldSegments('**inizio\nfine**'), [
        (text: '**inizio\nfine**', bold: false),
      ]);
    });
  });

  /// I pezzi in grassetto di tutti i testi sullo schermo.
  List<String> boldTexts(WidgetTester tester) {
    final out = <String>[];
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      t.textSpan?.visitChildren((s) {
        if (s is TextSpan && s.text != null && s.style == readerBold) {
          out.add(s.text!);
        }
        return true;
      });
    }
    return out;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(360, 780),
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildTheme(brightness), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Il testo dell\'articolo mostra il grassetto senza asterischi', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const Scaffold(
        body: Column(
          children: [
            ReaderBody('**Disponibilità:** dal LUNEDÌ al VENERDÌ'),
            ReaderBody('Finisce 3 ** 2'),
          ],
        ),
      ),
    );
    expect(find.text('Disponibilità: dal LUNEDÌ al VENERDÌ'), findsOneWidget);
    expect(boldTexts(tester), ['Disponibilità:']);
    // Il resto ha il peso normale del testo.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ReaderBody).first,
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.text.style?.fontWeight, isNot(readerBold.fontWeight));
    // Asterischi spaiati: si vedono così come sono.
    expect(find.text('Finisce 3 ** 2'), findsOneWidget);
  });

  testWidgets('Organigramma: ogni riga diventa una voce, anche con / e .', (
    tester,
  ) async {
    final org = regolamento2026.firstWhere((a) => a.title == 'Organigramma');
    await pumpPage(tester, Scaffold(body: ReaderBody(org.body)));
    for (final line in org.body.split('\n')) {
      final i = line.indexOf(':');
      expect(find.text(line.substring(0, i)), findsOneWidget, reason: line);
      expect(find.text(line.substring(i + 1).trim()), findsOneWidget);
    }
    expect(find.text('RESPONSABILE TECNICO / TATTICO'), findsOneWidget);
    expect(find.text('RESP. COMUNICAZIONI E MARKETING'), findsOneWidget);

    // Anche nell'elenco il valore può avere il grassetto.
    await pumpPage(
      tester,
      const Scaffold(body: ReaderBody('FONDATORI: **Fabio**\nRESP. IT: Luca')),
    );
    expect(find.text('FONDATORI'), findsOneWidget);
    expect(boldTexts(tester), ['Fabio']);
  });

  group('Testi del regolamento 2026', () {
    test('sette articoli in ordine, nei limiti del database', () {
      expect(
        [for (final a in regolamento2026) a.title],
        [
          'Regolamento ufficiale 2026',
          'Organigramma',
          'Art. 1 – Presenza e comunicazione',
          'Art. 2 – Comportamento e disciplina',
          'Art. 3 – Dinamiche di gioco',
          'Art. 4 – Gestione della squadra e sanzioni',
          'Art. 5 – Candidature staff e obiettivi',
        ],
      );
      for (final a in regolamento2026) {
        expect(a.title.length, inInclusiveRange(1, 120), reason: a.title);
        expect(a.body.length, inInclusiveRange(1, 8000), reason: a.title);
        expect(a.body, a.body.trim(), reason: a.title);
        expect(a.body.contains('  '), isFalse, reason: a.title);
        // Ogni grassetto si chiude sulla stessa riga: nessun asterisco a vista.
        for (final line in a.body.split('\n')) {
          expect('**'.allMatches(line).length.isEven, isTrue, reason: line);
          expect(
            boldSegments(line).any((s) => s.text.contains('*')),
            isFalse,
            reason: line,
          );
        }
      }
      final all = [
        for (final a in regolamento2026) a.body,
        storia2026,
      ].join('\n');
      for (final typo in [
        'raà',
        'eà ',
        'del MILANAC.',
        'LUNEDI ',
        'VENERDI ',
        'fatti salvi',
        'responsabilita',
        'partite successive',
        'non autorizzato',
        '.IL ',
      ]) {
        expect(all.contains(typo), isFalse, reason: typo);
      }
      expect(organigrammaOf(_version())?.title, 'Organigramma');
    });

    test('gli stessi testi della migrazione 0033', () {
      final sql = File('supabase/migrations/0033_regolamento_2026.sql')
          .readAsStringSync();
      final rows = RegExp(
        r"\((\d+), '([^']*)', \$txt\$(.*?)\$txt\$\)",
        dotAll: true,
      ).allMatches(sql).toList();
      expect(
        [for (final m in rows) int.parse(m.group(1)!)],
        [for (var i = 0; i < regolamento2026.length; i++) i],
      );
      expect([
        for (final m in rows) (title: m.group(2)!, body: m.group(3)!),
      ], regolamento2026);
      final storia = RegExp(
        r"\('storia',\s*\$txt\$(.*?)\$txt\$",
        dotAll: true,
      ).firstMatch(sql);
      expect(storia?.group(1), storia2026);
    });

    test('la storia: la citazione e i cenni storici', () {
      final paragraphs = storia2026.split('\n\n');
      expect(paragraphs, hasLength(2));
      expect(paragraphs.first, startsWith('“I nostri colori saranno'));
      expect(paragraphs.last, startsWith('Il club nasce nel 2025'));
      expect(paragraphs.last, contains('il rosso, il nero ed il bianco'));
    });

    test('la demo mostra lo stesso regolamento e la stessa storia', () async {
      final latest = await DemoRulesRepository.instance.latest();
      expect([
        for (final a in latest!.articles) (title: a.title, body: a.body),
      ], regolamento2026);
      expect(await DemoPagesRepository().load(ClubPage.storia), storia2026);
    });
  });

  for (final width in [320.0, 360.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Regolamento 2026 a ${width.toInt()} dp (${brightness.name}): '
        'grassetto e niente che sborda',
        (tester) async {
          await pumpPage(
            tester,
            Scaffold(body: RulesReader(version: _version())),
            size: Size(width, 640),
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('REGOLAMENTO UFFICIALE 2026'), findsOneWidget);
          expect(find.textContaining('**'), findsNothing);
          expect(
            boldTexts(tester),
            containsAll([
              'Se stai leggendo questo documento, significa che hai passato '
                  'le selezioni e sei entrato nel MILANAC.',
              'Disponibilità:',
              'durante',
              'Suddivisione delle responsabilità:',
              'BENVENUTO IN FAMIGLIA!',
            ]),
          );
          final list = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          list.position.jumpTo(list.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // La storia con l'organigramma sotto.
          await pumpPage(
            tester,
            Scaffold(
              body: StoryReader(
                text: storia2026,
                organigramma: organigrammaOf(_version()),
              ),
            ),
            size: Size(width, 640),
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          expect(find.textContaining('nasce nel 2025'), findsOneWidget);
          expect(find.textContaining('I nostri colori'), findsOneWidget);
          expect(find.text('RESPONSABILE TORNEI E AMICHEVOLI'), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'Editor a 320 dp: anteprima senza asterischi e aiuto sul grassetto',
    (tester) async {
      await pumpPage(
        tester,
        const RulesEditorPage(),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Art. 1 – Presenza e comunicazione'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
      expect(boldTexts(tester), contains('Disponibilità:'));

      await tester.tap(find.text('Nuovo articolo'));
      await tester.pumpAndSettle();
      final help = find.text('Per il grassetto: **testo**');
      expect(help, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(help).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Accettazione a 320 dp: lo stesso grassetto, fino in fondo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
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
    container.read(routerProvider).go('/regolamento/accetta');
    await tester.pumpAndSettle();

    expect(find.text('Ho letto e accetto'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(
      boldTexts(tester),
      containsAll(['Disponibilità:', 'BENVENUTO IN FAMIGLIA!']),
    );
    final reader = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(RulesReader),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    reader.position.jumpTo(reader.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Scorri fino in fondo per poter accettare'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

RulesVersion _version() => RulesVersion(
  number: 2,
  publishedAt: DateTime(2026, 11, 4),
  articles: [
    for (final (i, a) in regolamento2026.indexed)
      RulesArticle(sortOrder: i, title: a.title, body: a.body),
  ],
);
