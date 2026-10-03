import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Apre il menu laterale e va alla sezione [title], scorrendo il menu se serve.
Future<void> goToSection(WidgetTester tester, String title) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  final item = find.descendant(
    of: find.byType(Drawer),
    matching: find.text(title),
  );
  await tester.scrollUntilVisible(
    item,
    100,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}
