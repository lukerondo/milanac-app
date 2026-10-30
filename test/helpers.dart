import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Schede della barra in basso.
const _tabs = {'Home', 'Presenze', 'Partite', 'Chat', 'Club'};

/// Sezioni che stanno nella scheda Partite (selettore in alto).
const _partite = {'Calendario', 'Risultati', 'Tornei'};

/// Nomi storici delle sezioni (usati dai test) → voce nella pagina Club.
const _clubAliases = {
  'Rosa completa': 'Rosa',
  'Tattiche & Build': 'Tattiche',
  'Regolamento & Storia': 'Regolamento e Storia',
};

/// Tocca una scheda della barra in basso (prima chiude le pagine a schermo intero
/// aperte sopra, come profilo, impostazioni o una conversazione).
Future<void> tapTab(WidgetTester tester, String tab) async {
  for (var i = 0; i < 5 && find.byType(NavigationBar).evaluate().isEmpty; i++) {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)),
  );
  await tester.pumpAndSettle();
}

/// Apre [path] con il router dell'app (per le pagine raggiunte da notifiche e link).
Future<void> goToPath(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
}

/// Va alla sezione [title]: dalla barra in basso, dal selettore di Partite,
/// dalla pagina Club oppure (profilo e carta) dalla foto in alto a destra.
Future<void> goToSection(WidgetTester tester, String title) async {
  if (_tabs.contains(title)) return tapTab(tester, title);
  if (_partite.contains(title)) {
    await tapTab(tester, 'Partite');
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
    return;
  }
  if (title == 'Formazione') return goToPath(tester, '/formazione');
  if (title == 'La mia carta' || title == 'Profilo') {
    if (find.text('IL TUO PROFILO').evaluate().isNotEmpty) return;
    if (find.byTooltip('Il tuo profilo').evaluate().isEmpty) {
      await tapTab(tester, 'Home');
    }
    await tester.tap(find.byTooltip('Il tuo profilo').first);
    await tester.pumpAndSettle();
    return;
  }
  if (title == 'Impostazioni') {
    await goToSection(tester, 'Profilo');
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    return;
  }
  await tapTab(tester, 'Club');
  final item = find.text(_clubAliases[title] ?? title);
  await tester.scrollUntilVisible(
    item,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  // La voce può essere già "trovata" ma ancora sotto la barra in basso: la si porta
  // in vista prima di toccarla.
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// Scorre fino a [finder], lo porta bene in vista (non sotto la barra in basso) e lo tocca.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
