import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/features/carta/card_attributes.dart';
import 'package:milanac/features/carta/card_photo.dart';
import 'package:milanac/features/carta/fut_card.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_page.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/member_photo.dart';

import 'helpers.dart';
import 'rosa_view.dart';

Future<ProviderContainer> _startApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Una foto "già scontornata": un cerchio rosso su fondo trasparente (PNG).
Future<Uint8List> _cutoutPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawCircle(
    const Offset(50, 70),
    42,
    Paint()..color = const Color(0xFFC8102E),
  );
  final image = await recorder.endRecording().toImage(100, 140);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Lascia lavorare il motore (decodifica e disegno delle immagini, che nei test
/// non avanzano con il tempo finto) finché [ready] non è vero.
Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 60 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'il motore non ha finito in tempo');
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('statistiche: sigle da portiere, bonus fino a 99, overall suggerito dal '
      'ruolo', () {
    expect(cardStatLabels('ATT'), ['VEL', 'TIR', 'PAS', 'DRI', 'DIF', 'FIS']);
    expect(cardStatLabels('POR'), ['TUF', 'PRE', 'RIN', 'RIF', 'VEL', 'PIA']);
    expect(statsWithBonus([97, 50, 1, 60, 70, 80], 5), [99, 55, 6, 65, 75, 85]);
    expect(statsWithBonus(null, 5), isNull);
    // Stesse statistiche, ruolo diverso: l'attaccante vale per tiro e velocità,
    // il difensore centrale per difesa e fisico.
    const stats = [90, 90, 60, 80, 30, 70];
    expect(suggestedOverall(stats, 'ATT'), 83);
    expect(suggestedOverall(stats, 'DC'), 52);
    expect(suggestedOverall(null, 'ATT'), isNull);
    expect(parseCardStats([88, 86, 74, 83, 38, 76]), [88, 86, 74, 83, 38, 76]);
    expect(parseCardStats([1, 2, 3]), isNull);
    expect(parseCardStats(null), isNull);
  });

  testWidgets('La carta mostra le sei statistiche (da portiere) con il bonus '
      'della carta speciale', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: FutCard(
                  member: Member(
                    id: 'x',
                    displayName: 'Bianchi',
                    role: ClubRole.giocatore,
                    joinedAt: DateTime(2026),
                    overall: 80,
                    fieldPosition: 'POR',
                    cardStats: const [82, 79, 70, 84, 50, 81],
                    nationality: 'IT',
                  ),
                  special: CardSpecial.neroOro,
                  bonus: 3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('83'), findsOneWidget, reason: 'overall 80 + 3');
    expect(find.text('TUF'), findsOneWidget);
    expect(find.text('85'), findsOneWidget, reason: 'tuffo 82 + 3');
    expect(
      find.bySemanticsLabel(
        'Carta nero e oro: Bianchi, 83, POR, Italia, TUF 85, PRE 82, RIN 73, '
        'RIF 87, VEL 53, PIA 84',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Direttivo: le statistiche dalla carta di un giocatore, con '
      'l\'overall suggerito dal ruolo', (tester) async {
    final container = await _startApp(tester);
    Member rossiNow() =>
        container.read(rosaProvider).value!.firstWhere((m) => m.id == 'p2');
    await goToSection(tester, 'Rosa completa');
    await showRosaAs(tester, RosaView.elenco);
    await tester.scrollUntilVisible(
      find.text('Marco Rossi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marco Rossi'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Modifica carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifica carta'));
    await tester.pumpAndSettle();
    expect(find.text('STATISTICHE DELLA CARTA'), findsOneWidget);
    expect(rossiNow().cardStats, isNull);

    // VEL al minimo (il primo cursore è l'overall).
    final vel = find.byType(Slider).at(1);
    await tester.ensureVisible(vel);
    await tester.pumpAndSettle();
    await tester.drag(vel, const Offset(-600, 0));
    await tester.pumpAndSettle();
    final suggest = find.textContaining('Usa l\'overall suggerito');
    expect(suggest, findsOneWidget);
    await tester.tap(suggest);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Salva la carta'));
    await tester.tap(find.text('Salva la carta'));
    await tester.pumpAndSettle();

    final saved = rossiNow();
    expect(saved.cardStats, isNotNull);
    expect(saved.cardStats!.first, 1);
    expect(
      saved.overall,
      suggestedOverall(saved.cardStats, saved.fieldPosition),
    );
  });

  testWidgets('Foto della carta: un PNG già scontornato va sulla carta, e si '
      'può togliere (torna il volto)', (tester) async {
    final png = (await tester.runAsync(_cutoutPng))!;
    final container = await _startApp(
      tester,
      overrides: [
        cardPhotoPickerProvider.overrideWithValue((source) async => png),
      ],
    );
    Member meNow() =>
        container.read(rosaProvider).value!.firstWhere((m) => m.id == 'demo');
    await goToSection(tester, 'La mia carta');
    await tester.ensureVisible(find.text('Metti la tua foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metti la tua foto'));
    await tester.pumpAndSettle();
    expect(find.byType(CardPhotoPage), findsOneWidget);

    await tester.tap(find.text('Scegli una foto'));
    await _waitFor(
      tester,
      () => find.text('Salva sulla carta').evaluate().isNotEmpty,
    );
    // Già senza sfondo: l'app non lo toglie di nuovo e lo dice.
    expect(find.textContaining('Sfondo tolto'), findsOneWidget);
    await tester.tap(find.text('Salva sulla carta'));
    await _waitFor(tester, () => meNow().avatarPath != null);
    await tester.pumpAndSettle();
    final path = meNow().avatarPath!;
    expect(path, startsWith('demo/'));
    expect(path, endsWith('.png'));
    expect(demoPhotos[path], isNotNull);
    expect(find.byType(CardPhotoPage), findsNothing);
    expect(find.text('Cambia la foto'), findsOneWidget);

    // Tolta: sulla carta torna il volto disegnato (prima sparisce l'avviso).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambia la foto'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Togli la foto'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CardPhotoPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.textContaining('Togli la foto'));
    await tester.pumpAndSettle();
    expect(meNow().avatarPath, isNull);
    expect(demoPhotos.containsKey(path), isFalse);
  });

  testWidgets('Telefono stretto (320 dp): la carta si stringe e resta intera', (
    tester,
  ) async {
    await _startApp(tester);
    tester.view.physicalSize = const Size(960, 2340);
    await tester.pumpAndSettle();
    await goToSection(tester, 'La mia carta');
    expect(tester.takeException(), isNull);
    final card = tester.getSize(find.byType(FutCard));
    expect(card.width, lessThanOrEqualTo(320 - 32 + .5));
    expect(
      card.height / card.width,
      closeTo(FutCard.height / FutCard.width, .01),
    );
  });
}
