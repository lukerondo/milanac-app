import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/regolamento/rules_reader.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';
import 'package:milanac/features/traguardi/achievements.dart';
import 'package:milanac/features/walkout/celebrations.dart';
import 'package:milanac/features/walkout/walkout_page.dart';
import 'package:milanac/main.dart';

/// L'ingresso nel club finisce con il walkout: dopo il regolamento la Home resta coperta
/// finché non parte la carta di chi è entrato, una volta sola per telefono.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  const cover = 'Prepariamo la tua carta…';

  /// La rosa come arriva dal server: chi entra c'è, con l'overall che ha dichiarato.
  final roster = [
    Member(
      id: 'demo',
      displayName: 'Demo Direttivo',
      role: ClubRole.direttivo,
      joinedAt: DateTime(2026, 11, 1),
      overall: 82,
      fieldPosition: 'CC',
    ),
  ];

  /// L'app con le feste accese (in demo sono spente) e solo il walkout di benvenuto:
  /// niente carte speciali né traguardi, che hanno le loro prove.
  Future<ProviderContainer> start(
    WidgetTester tester, {
    required MemoryFlags flags,
    Stream<List<Member>>? rosa,
    bool entering = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        celebrationsEnabledProvider.overrideWithValue(true),
        localFlagsProvider.overrideWithValue(flags),
        activeSpecialCardProvider.overrideWith((ref, id) => null),
        achievementsProvider.overrideWith((ref, id) => null),
        rosaProvider.overrideWith((ref) => rosa ?? Stream.value(roster)),
      ],
    );
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    if (entering) container.read(entranceProvider.notifier).begin();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    return container;
  }

  /// Qualche fotogramma (il walkout e la copertura hanno animazioni che non finiscono:
  /// niente pumpAndSettle finché sono a schermo).
  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Apre il pacchetto, guarda la carta e chiude il walkout.
  Future<void> watchWalkout(WidgetTester tester) async {
    await tester.tap(find.text('Tocca per aprire'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Dopo il regolamento: il walkout con la propria carta è l\'ultimo '
    'passo, poi la Home; non torna una seconda volta',
    (tester) async {
      final flags = MemoryFlags();
      final container = await start(tester, flags: flags);
      await frames(tester);

      // Il walkout di benvenuto è partito e la copertura se n'è andata.
      expect(find.byType(WalkoutPage), findsOneWidget);
      expect(find.text(cover), findsNothing);
      expect(find.text('Tocca per aprire'), findsOneWidget);
      expect(container.read(entranceProvider), isFalse);
      expect(flags.values[walkoutKey('demo')], '82');

      await watchWalkout(tester);
      expect(find.byType(WalkoutPage), findsNothing);
      expect(find.text('MILANAC PRO CLUB'), findsOneWidget);

      // La rosa si aggiorna (tempo reale), l'app si riapre: il benvenuto non si ripete.
      container.invalidate(rosaProvider);
      await tester.pumpAndSettle();
      expect(find.byType(WalkoutPage), findsNothing);
    },
  );

  testWidgets(
    'La carta arriva dopo la Home: intanto la Home resta coperta, poi '
    'parte il walkout',
    (tester) async {
      final flags = MemoryFlags();
      final rosa = StreamController<List<Member>>();
      addTearDown(rosa.close);
      final container = await start(tester, flags: flags, rosa: rosa.stream);
      await frames(tester);

      // Rosa non ancora arrivata: niente walkout, e la Home non si vede né si tocca.
      expect(find.text(cover), findsOneWidget);
      expect(find.byType(WalkoutPage), findsNothing);
      expect(container.read(entranceProvider), isTrue);
      expect(flags.values[walkoutKey('demo')], isNull);
      await tester.tapAt(
        const Offset(180, 740),
      ); // la barra in basso, sotto la copertura
      await frames(tester, 2);
      expect(find.text(cover), findsOneWidget);

      rosa.add(roster);
      await frames(tester);
      expect(find.byType(WalkoutPage), findsOneWidget);
      expect(find.text(cover), findsNothing);
      expect(container.read(entranceProvider), isFalse);
      expect(flags.values[walkoutKey('demo')], '82');

      await watchWalkout(tester);
      expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    },
  );

  testWidgets(
    'Senza rete la Home non resta coperta per sempre: dopo l\'attesa si '
    'scopre, e il walkout parte quando la carta arriva',
    (tester) async {
      final flags = MemoryFlags();
      final rosa = StreamController<List<Member>>();
      addTearDown(rosa.close);
      final container = await start(tester, flags: flags, rosa: rosa.stream);
      await frames(tester);
      expect(find.text(cover), findsOneWidget);

      await tester.pump(const Duration(seconds: 8));
      await frames(tester);
      expect(find.text(cover), findsNothing);
      expect(find.byType(WalkoutPage), findsNothing);
      expect(container.read(entranceProvider), isFalse);
      expect(
        flags.values[walkoutKey('demo')],
        isNull,
        reason: 'non ancora visto',
      );

      // La carta arriva più tardi: il benvenuto non è andato perso.
      rosa.add(roster);
      await frames(tester, 8);
      expect(find.byType(WalkoutPage), findsOneWidget);
      expect(flags.values[walkoutKey('demo')], '82');
      await watchWalkout(tester);
    },
  );

  testWidgets(
    'Walkout già visto su questo telefono: nessuna copertura che resta, '
    'nessun secondo benvenuto',
    (tester) async {
      final flags = MemoryFlags()..values[walkoutKey('demo')] = '82';
      final container = await start(tester, flags: flags);
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.byType(WalkoutPage), findsNothing);
      expect(find.text(cover), findsNothing);
      expect(container.read(entranceProvider), isFalse);
      expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    },
  );

  testWidgets(
    'Chi apre l\'app da membro (nessun ingresso in corso): il benvenuto '
    'parte lo stesso, senza copertura',
    (tester) async {
      final flags = MemoryFlags();
      await start(tester, flags: flags, entering: false);
      await tester.pump();
      expect(find.text(cover), findsNothing);
      await frames(tester, 8);
      expect(find.byType(WalkoutPage), findsOneWidget);
      expect(find.text(cover), findsNothing);
      await watchWalkout(tester);
    },
  );

  group('Il regolamento', () {
    Future<ProviderContainer> rulesPage(
      WidgetTester tester, {
      Profile? profile,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          if (profile != null)
            profileProvider.overrideWith((ref) => Stream.value(profile)),
        ],
      );
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
      return container;
    }

    Future<void> readAndAccept(WidgetTester tester) async {
      await tester.drag(
        find.descendant(
          of: find.byType(RulesReader),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -20000),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ho letto e accetto'));
      await tester.pumpAndSettle();
    }

    testWidgets('accettato da chi si è appena registrato: comincia l\'ingresso '
        '(il walkout sarà l\'ultimo passo)', (tester) async {
      final container = await rulesPage(
        tester,
        profile: const Profile(
          id: 'demo',
          displayName: 'NUOVO',
          role: ClubRole.pending,
          registrationCompleted: true,
          overall: 82,
        ),
      );
      // In demo le feste sono spente e l'ingresso si chiude subito: si guarda che sia
      // cominciato.
      final entrance = <bool>[];
      container.listen(entranceProvider, (_, on) => entrance.add(on));
      await readAndAccept(tester);
      expect(entrance.first, isTrue);
    });

    testWidgets('accettato da chi è già nel club (versione nuova): nessun '
        'ingresso, nessun walkout', (tester) async {
      final container = await rulesPage(tester);
      final entrance = <bool>[];
      container.listen(entranceProvider, (_, on) => entrance.add(on));
      await readAndAccept(tester);
      expect(entrance, isEmpty);
      expect(find.text('MILANAC PRO CLUB'), findsOneWidget);
    });
  });
}
