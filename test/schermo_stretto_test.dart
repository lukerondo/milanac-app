import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/auth/login_page.dart';
import 'package:milanac/features/impostazioni/impostazioni_page.dart';
import 'package:milanac/shared/ui.dart';

/// Testi misurati con i caratteri veri, su un telefono stretto (360 dp).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('it');
    // Nei test il carattere predefinito è un segnaposto: si carica Barlow per davvero,
    // così le misure dei testi sono quelle del telefono.
    final barlow = FontLoader(bodyFont);
    for (final w in ['400', '500', '600', '700']) {
      barlow.addFont(rootBundle.load('assets/fonts/Barlow-$w.ttf'));
    }
    await barlow.load();
  });

  void phone360(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('Aspetto a 360 dp: le tre scelte si leggono intere', (
    tester,
  ) async {
    phone360(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildTheme(), home: const ImpostazioniPage()),
      ),
    );
    await tester.pumpAndSettle();
    Finder label(String text) => find.descendant(
      of: find.byType(SegmentedTabs),
      matching: find.text(text),
    );
    await tester.ensureVisible(find.byType(SegmentedTabs));
    await tester.pumpAndSettle();
    for (final a in Appearance.values) {
      final text = tester.renderObject<RenderParagraph>(label(a.label));
      expect(text.didExceedMaxLines, isFalse, reason: a.label);
    }

    // Con l'etichetta di prima la terza scelta veniva tagliata ("Come il telef…").
    final auto = tester.renderObject<RenderParagraph>(label('Automatico'));
    final before = TextPainter(
      text: TextSpan(text: 'Come il telefono', style: auto.text.style),
      textDirection: TextDirection.ltr,
      textScaler: auto.textScaler,
    )..layout();
    expect(before.width, greaterThan(auto.constraints.maxWidth));
    before.dispose();
  });

  testWidgets('"Password dimenticata?", "Mostra" e i suggerimenti in Barlow', (
    tester,
  ) async {
    phone360(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildTheme(), home: const LoginPage()),
      ),
    );
    await tester.pumpAndSettle();
    String? family(String text) => tester
        .renderObject<RenderParagraph>(find.text(text))
        .text
        .style
        ?.fontFamily;
    expect(family('Password dimenticata?'), bodyFont);
    expect(family('Mostra'), bodyFont);
    for (final b in Brightness.values) {
      expect(buildTheme(b).tooltipTheme.textStyle?.fontFamily, bodyFont);
    }
  });
}
