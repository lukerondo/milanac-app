import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/formazione/perspective_pitch.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayAt;

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('Prospettiva: in fondo il campo è più stretto e le righe più fitte', () {
    const size = Size(320, 400);
    const p = PitchPerspective(size);
    final farL = p.project(0, 0), farR = p.project(1, 0);
    final nearL = p.project(0, 1), nearR = p.project(1, 1);
    expect(
      farR.dx - farL.dx,
      closeTo((nearR.dx - nearL.dx) / PitchPerspective.ratio, .001),
    );
    expect(farL.dy, PitchPerspective.topPad);
    expect(nearL.dy, size.height - PitchPerspective.bottomPad);
    // La metà campo sta sopra la metà dello schermo: la parte lontana si schiaccia.
    expect(p.project(.5, .5).dy, lessThan((farL.dy + nearL.dy) / 2));
    // Centrato, simmetrico.
    expect(p.project(.5, .3).dx, size.width / 2);
    expect(p.nearness(0), closeTo(0, 1e-9));
    expect(p.nearness(1), closeTo(1, 1e-9));
    expect(PitchPerspective.cardScaleAt(0), .7);
    expect(PitchPerspective.cardScaleAt(1), 1);
  });

  testWidgets('Formazione in prospettiva: mini carte in piedi, più grandi '
      'davanti e sopra quelle in fondo', (tester) async {
    await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'Formazione');
    await tester.tap(find.text('Prepara la formazione'));
    await tester.pumpAndSettle();

    Rect cardOf(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(FittedBox))
          .last,
    );
    final keeper = cardOf('1 Neri'), striker = cardOf('9 Rossi');
    // Il portiere è vicino (in basso, più grande), l'attaccante in fondo.
    expect(keeper.top, greaterThan(striker.top));
    expect(keeper.height, greaterThan(striker.height));
    // Le carte vicine sono disegnate dopo: coprono quelle in fondo.
    final stackOrder = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(
      stackOrder.indexOf('1 Neri'),
      greaterThan(stackOrder.indexOf('9 Rossi')),
    );
    // Toccare la carta apre la scelta del giocatore, come prima.
    await tester.tap(find.text('9 Rossi'));
    await tester.pumpAndSettle();
    expect(find.text('Libera la posizione'), findsOneWidget);
  });
}
