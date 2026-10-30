import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/features/carta/live_card.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';

/// La matrice dell'inclinazione della carta.
Matrix4 tiltOf(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(LiveCard),
        matching: find.byType(Transform),
      ),
    )
    .transform;

Widget card({bool still = false, CardSpecial? special}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Center(
      child: SizedBox(
        width: 210,
        child: LiveCard(
          special: special,
          child: const SizedBox(width: 210, height: 300),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('Carta viva: il riflesso passa da solo e si ferma; poi ripassa', (
    tester,
  ) async {
    await tester.pumpWidget(card(special: CardSpecial.neroOro));
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'riflesso in corso',
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'poi ferma');
    await tester.pump(LiveCard.sweepEvery);
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'ripassa');
    await tester.pumpAndSettle();
  });

  testWidgets('Con "riduci animazioni" il riflesso non parte da solo', (
    tester,
  ) async {
    await tester.pumpWidget(card(still: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(LiveCard.sweepEvery);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'La carta si inclina seguendo il dito e torna dritta lasciandola',
    (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();
      expect(tiltOf(tester), Matrix4.identity()..setEntry(3, 2, .0012));

      final box = tester.getRect(find.byType(LiveCard));
      final gesture = await tester.startGesture(box.center);
      await gesture.moveTo(box.centerRight - const Offset(2, 0));
      await tester.pump();
      final tilted = tiltOf(tester);
      // Il dito a destra: la carta ruota attorno all'asse verticale.
      expect(tilted.entry(0, 2).abs(), greaterThan(.1));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tiltOf(tester).entry(0, 2).abs(), lessThan(1e-6));
    },
  );

  test('Riflessi e brillii si disegnano per tutte le carte', () {
    for (final special in [null, CardSpecial.neroOro, CardSpecial.blu]) {
      for (final sweep in [null, 0.0, .3, .6, 1.0]) {
        final recorder = ui.PictureRecorder();
        CardShinePainter(
          sweep: sweep,
          tilt: const Offset(.5, -.4),
          special: special,
        ).paint(Canvas(recorder), const Size(210, 300));
        recorder.endRecording().dispose();
      }
    }
    const a = CardShinePainter(sweep: .2, tilt: Offset.zero);
    expect(
      a.shouldRepaint(const CardShinePainter(sweep: .2, tilt: Offset.zero)),
      isFalse,
    );
    expect(
      a.shouldRepaint(const CardShinePainter(sweep: .3, tilt: Offset.zero)),
      isTrue,
    );
  });
}
