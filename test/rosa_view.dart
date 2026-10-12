import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/features/rosa/rosa_page.dart';

/// Mostra la Rosa come elenco o come carte: con il pulsante della barra in alto
/// ([RosaViewButton]) quando c'è, altrimenti scegliendo la vista come fa il pulsante.
Future<void> showRosaAs(WidgetTester tester, RosaView view) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RosaPage)),
  );
  if (container.read(rosaViewProvider) == view) return;
  final button = find.byType(RosaViewButton);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button.first);
  } else {
    container.read(rosaViewProvider.notifier).set(view);
  }
  await tester.pumpAndSettle();
}
