import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/features/intro/intro_page.dart';
import 'package:milanac/features/intro/intro_state.dart';

void main() {
  testWidgets('Intro: cori e speaker accesi; il pulsante spegne l\'audio senza '
      'saltare l\'intro, e la volta dopo resta spento', (tester) async {
    final flags = MemoryFlags();
    Widget intro(Key key) => ProviderScope(
      overrides: [localFlagsProvider.overrideWithValue(flags)],
      child: MaterialApp(home: IntroPage(key: key)),
    );

    await tester.pumpWidget(intro(UniqueKey()));
    await tester.pump();
    expect(find.byTooltip('Spegni l\'audio'), findsOneWidget);
    expect(find.text('Salta'), findsOneWidget);

    await tester.tap(find.byTooltip('Spegni l\'audio'));
    await tester.pump();
    expect(find.byTooltip('Accendi l\'audio'), findsOneWidget);
    expect(flags.values[IntroPage.mutedFlag], '1');
    // Il tocco sul pulsante non conta come "salta".
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IntroPage)),
    );
    expect(container.read(introDoneProvider), isFalse);

    // Alla prossima apertura dell'app l'intro parte già senza audio.
    await tester.pumpWidget(intro(UniqueKey()));
    await tester.pump();
    expect(find.byTooltip('Accendi l\'audio'), findsOneWidget);

    // E si riaccende.
    await tester.tap(find.byTooltip('Accendi l\'audio'));
    await tester.pump();
    expect(flags.values[IntroPage.mutedFlag], '0');
    expect(find.byTooltip('Spegni l\'audio'), findsOneWidget);
  });
}
