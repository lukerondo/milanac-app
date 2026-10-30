import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayInItalyAt;

/// Sala Direttivo → Rosa e squadre (la demo è del Direttivo).
Future<DemoRosaRepository> openRoster(
  WidgetTester tester, {
  void Function(DemoRosaRepository repo)? setUp,
}) async {
  final container = await startAppAt(tester, todayInItalyAt(17));
  final repo = container.read(rosaRepositoryProvider) as DemoRosaRepository;
  setUp?.call(repo);
  await goToSection(tester, 'Sala Direttivo');
  await scrollAndTap(tester, find.text('Rosa e squadre'));
  return repo;
}

Future<Member?> memberOf(DemoRosaRepository repo, String id) async =>
    (await repo.watchAll().first).where((m) => m.id == id).firstOrNull;

Future<void> openEditor(WidgetTester tester, String name) async {
  // La lista costruisce le schede solo quando arrivano in vista.
  await tester.scrollUntilVisible(
    find.text(name),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
  expect(find.text('Modifica membro'), findsOneWidget);
}

Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('Promozione nel Direttivo con le etichette, poi retrocessione', (
    tester,
  ) async {
    final repo = await openRoster(tester);
    await openEditor(tester, 'Marco Rossi');

    await tester.tap(find.text('Direttivo').last);
    await tester.pumpAndSettle();
    expect(find.text('Ruoli nel Direttivo (almeno uno)'), findsOneWidget);
    expect(
      find.textContaining('avrà tutti i poteri del Direttivo'),
      findsOneWidget,
    );
    // Senza etichette non si salva.
    await tapInSheet(tester, find.text('Salva'));
    expect(find.text('Scegli almeno un ruolo nel Direttivo.'), findsOneWidget);
    expect((await memberOf(repo, 'p2'))!.role, ClubRole.giocatore);

    await tapInSheet(tester, find.widgetWithText(FilterChip, 'Capitano'));
    await tapInSheet(tester, find.text('Salva'));
    expect(find.text('Modifica membro'), findsNothing, reason: 'foglio chiuso');
    var p2 = (await memberOf(repo, 'p2'))!;
    expect(p2.role, ClubRole.direttivo);
    expect(p2.direttivoRoles, [DirettivoRole.capitano]);

    // Retrocessione: le etichette si azzerano.
    await openEditor(tester, 'Marco Rossi');
    await tester.tap(find.text('Giocatore').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('perderà i poteri del Direttivo'),
      findsOneWidget,
    );
    await tapInSheet(tester, find.text('Salva'));
    p2 = (await memberOf(repo, 'p2'))!;
    expect(p2.role, ClubRole.giocatore);
    expect(p2.direttivoRoles, isEmpty);
  });

  testWidgets('L\'ultimo del Direttivo non si retrocede; sul proprio profilo '
      'niente rimozione né eliminazione', (tester) async {
    final repo = await openRoster(tester);
    await openEditor(tester, 'Demo Direttivo');
    expect(find.text('Elimina l\'account'), findsNothing);
    expect(find.text('Rimuovi dalla rosa'), findsNothing);
    await tester.tap(find.text('Giocatore').last);
    await tester.pumpAndSettle();
    await tapInSheet(tester, find.text('Salva'));
    expect(find.textContaining(lastDirettivoMessage), findsOneWidget);
    expect((await memberOf(repo, 'demo'))!.role, ClubRole.direttivo);
  });

  testWidgets('Eliminazione dell\'account di un membro con doppia conferma', (
    tester,
  ) async {
    final repo = await openRoster(tester);
    await openEditor(tester, 'Luca Bianchi');
    await tapInSheet(tester, find.text('Elimina l\'account'));
    expect(find.text('Eliminare l\'account di Luca Bianchi?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Elimina l\'account');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Ho capito, è definitivo'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Account di Luca Bianchi eliminato.'), findsOneWidget);
    expect(await memberOf(repo, 'p3'), isNull);
    expect(find.text('Modifica membro'), findsNothing);
  });

  testWidgets('Chi si è registrato ma non è entrato: il Direttivo lo vede e '
      'ne elimina l\'account', (tester) async {
    final repo = await openRoster(
      tester,
      setUp: (repo) => repo.add(
        Member(
          id: 'x1',
          displayName: 'sconosciuto',
          role: ClubRole.pending,
          joinedAt: DateTime(2026, 10, 1),
          registrationCompleted: false,
        ),
      ),
    );
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Registrazione non completata'),
      300,
      scrollable: page,
    );
    expect(find.text('IN ATTESA DI ENTRARE'), findsOneWidget);
    await tester.tap(find.byTooltip('Elimina l\'account di sconosciuto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho capito, è definitivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina l\'account'));
    await tester.pumpAndSettle();
    expect(find.text('Account di sconosciuto eliminato.'), findsOneWidget);
    expect(await memberOf(repo, 'x1'), isNull);
    expect(find.text('IN ATTESA DI ENTRARE'), findsNothing);
  });

  testWidgets('Il Direttivo toglie la foto del profilo di un membro', (
    tester,
  ) async {
    final repo = await openRoster(tester);
    final p2 = (await memberOf(repo, 'p2'))!;
    expect(p2.role, ClubRole.giocatore);
    expect(p2.direttivoRoles, isEmpty);
  });

  testWidgets('L\'ultimo del Direttivo non si retrocede; sul proprio profilo '
      'niente rimozione né eliminazione', (tester) async {
    final repo = await openRoster(tester);
    await openEditor(tester, 'Demo Direttivo');
    expect(find.text('Elimina l\'account'), findsNothing);
    expect(find.text('Rimuovi dalla rosa'), findsNothing);
    await tester.tap(find.text('Giocatore').last);
    await tester.pumpAndSettle();
    await tapInSheet(tester, find.text('Salva'));
    expect(find.textContaining(lastDirettivoMessage), findsOneWidget);
    expect((await memberOf(repo, 'demo'))!.role, ClubRole.direttivo);
  });

  testWidgets('Eliminazione dell\'account di un membro con doppia conferma', (
    tester,
  ) async {
    final repo = await openRoster(tester);
    await openEditor(tester, 'Luca Bianchi');
    await tapInSheet(tester, find.text('Elimina l\'account'));
    expect(find.text('Eliminare l\'account di Luca Bianchi?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Elimina l\'account');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Ho capito, è definitivo'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Account di Luca Bianchi eliminato.'), findsOneWidget);
    expect(await memberOf(repo, 'p3'), isNull);
    expect(find.text('Modifica membro'), findsNothing);
  });

  testWidgets('Chi si è registrato ma non è entrato: il Direttivo lo vede e '
      'ne elimina l\'account', (tester) async {
    final repo = await openRoster(
      tester,
      setUp: (repo) => repo.add(
        Member(
          id: 'x1',
          displayName: 'sconosciuto',
          role: ClubRole.pending,
          joinedAt: DateTime(2026, 10, 1),
          registrationCompleted: false,
        ),
      ),
    );
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Registrazione non completata'),
      300,
      scrollable: page,
    );
    expect(find.text('IN ATTESA DI ENTRARE'), findsOneWidget);
    await tester.tap(find.byTooltip('Elimina l\'account di sconosciuto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ho capito, è definitivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina l\'account'));
    await tester.pumpAndSettle();
    expect(find.text('Account di sconosciuto eliminato.'), findsOneWidget);
    expect(await memberOf(repo, 'x1'), isNull);
    expect(find.text('IN ATTESA DI ENTRARE'), findsNothing);
  });

  testWidgets('Il Direttivo toglie la foto del profilo di un membro', (
    tester,
  ) async {
    final repo = await openRoster(tester);
    final p2 = (await memberOf(repo, 'p2'))!;
    await repo.uploadPhoto(p2, Uint8List.fromList([1, 2, 3]));
    await tester.pumpAndSettle();
    expect((await memberOf(repo, 'p2'))!.avatarPath, isNotNull);

    await openEditor(tester, 'Marco Rossi');
    await tapInSheet(tester, find.text('Togli la foto del profilo'));
    await tester.tap(find.widgetWithText(FilledButton, 'Togli la foto'));
    await tester.pumpAndSettle();
    expect(find.text('Foto tolta.'), findsOneWidget);
    expect((await memberOf(repo, 'p2'))!.avatarPath, isNull);
  });
}
