import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stemma: fuori dallo scudo è trasparente (niente quadrato nero sul tema '
      'chiaro), lo scudo resta pieno', () async {
    final bytes = File('assets/images/stemma_256.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final w = image.width, h = image.height;
    int alpha(int x, int y) => pixels.getUint8((y * w + x) * 4 + 3);

    for (final (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]) {
      expect(alpha(x, y), 0, reason: 'angolo $x,$y');
    }
    // Il centro dello scudo e le scritte restano pieni.
    expect(alpha(w ~/ 2, h ~/ 2), 255);
    expect(alpha(w ~/ 2, h ~/ 4), 255);
    expect(alpha(w ~/ 4, h ~/ 2), 255);

    var clear = 0, solid = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = alpha(x, y);
        if (a == 0) clear++;
        if (a == 255) solid++;
      }
    }
    // Più di un quarto del tutto trasparente (il nero intorno), più di metà scudo pieno;
    // in mezzo solo l'alone sfumato del bordo.
    expect(clear / (w * h), greaterThan(.25));
    expect(solid / (w * h), greaterThan(.55));
    image.dispose();
    codec.dispose();
  });
}
