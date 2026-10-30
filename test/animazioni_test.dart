import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/haptics.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/features/carta/fut_card.dart';
import 'package:milanac/features/carta/mini_card.dart';
import 'package:milanac/shared/gold_loader.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;
import 'presenze_test.dart' show openPresenze, scrollTo;

/// Le vibrazioni chieste dall'app, per tipo (light, medium, heavy, selection).
List<String> _recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      haptics.add(switch (call.arguments) {
        'HapticFeedbackType.lightImpact' => 'light',
        'HapticFeedbackType.mediumImpact' => 'medium',
        'HapticFeedbackType.heavyImpact' => 'heavy',
        'HapticFeedbackType.selectionClick' => 'selection',
        _ => 'vibrate',
      });
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return haptics;
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  // Ogni test riparte con le vibrazioni accese (sono un'impostazione globale).
  tearDown(() => Haptics.enabled = true);

  testWidgets('Caricamento d\'oro: gira finché aspetta, fermo con la '
      'percentuale', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: GoldLoader())),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.byIcon(Icons.sports_soccer_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Caricamento'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Center(child: GoldLoader(size: 18, value: .4))),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Piccolo (nei pulsanti): solo l'arco, senza pallone.
    expect(find.byIcon(Icons.sports_soccer_rounded), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoldBar())));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Risposta alle presenze: vibra la conferma', (tester) async {
    final haptics = _recordHaptics(tester);
    await openPresenze(tester, todayInItalyAt(17));
    await scrollTo(
      tester,
      find.widgetWithText(OutlinedButton, 'Presente'),
      delta: -150,
    );
    haptics.clear();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Presente').first);
    await tester.pumpAndSettle();
    expect(find.text('La tua risposta: Presente'), findsOneWidget);
    // Il tocco sul pulsante, poi la risposta salvata.
    expect(haptics, ['selection', 'medium']);
  });

  testWidgets('Vibrazioni spente da Impostazioni: niente vibrazioni, e la '
      'scelta resta salvata', (tester) async {
    final haptics = _recordHaptics(tester);
    final container = await startAppAt(tester, todayInItalyAt(17));
    await goToSection(tester, 'Impostazioni');
    await tester.scrollUntilVisible(
      find.text('Vibrazioni'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Vibrazioni'));
    await tester.pumpAndSettle();
    expect(Haptics.enabled, isFalse);
    expect(
      await container.read(localFlagsProvider).getString('vibrazioni'),
      'no',
    );

    haptics.clear();
    await Haptics.confirm();
    await Haptics.goal();
    await Haptics.tap();
    expect(haptics, isEmpty);

    // Riaccese: un tocco per farlo sentire.
    await tester.tap(find.text('Vibrazioni'));
    await tester.pumpAndSettle();
    expect(Haptics.enabled, isTrue);
    expect(haptics, ['selection']);
  });

  testWidgets('Dalla Rosa la mini carta vola fino alla carta grande', (
    tester,
  ) async {
    await startAppAt(tester, todayInItalyAt(17));
    await goToSection(tester, 'Rosa completa');
    final mini = find.ancestor(
      of: find.text('MARCO ROSSI'),
      matching: find.byType(Hero),
    );
    expect(tester.widget<Hero>(mini).tag, cardHeroTag('p2'));

    await tester.tap(find.text('MARCO ROSSI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // In volo: la carta grande sta sopra le pagine, tra le due posizioni.
    expect(find.byType(FutCard), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final big = find.ancestor(
      of: find.byType(FutCard),
      matching: find.byType(Hero),
    );
    expect(tester.widget<Hero>(big.first).tag, cardHeroTag('p2'));
    expect(find.text('CARTA GIOCATORE'), findsOneWidget);

    // Indietro, la carta torna nella Rosa.
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('MARCO ROSSI'), findsOneWidget);
  });
}
