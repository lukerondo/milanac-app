import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/features/carta/card_stats.dart';
import 'package:milanac/features/carta/live_card.dart';
import 'package:milanac/features/carte/special_cards_repository.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/walkout/pack.dart';
import 'package:milanac/features/walkout/walkout_fx.dart';
import 'package:milanac/features/walkout/walkout_page.dart';

final _rossi = Member(
  id: 'p2',
  displayName: 'Marco Rossi',
  role: ClubRole.giocatore,
  fieldPosition: 'ATT',
  shirtNumber: 9,
  joinedAt: DateTime(2025, 2, 3),
  overall: 82,
);

const _stats = CardStats(
  presence: 80,
  punctuality: 90,
  nights: 20,
  goals: 12,
  months: 10,
  winRate: 60,
);

/// Una pagina con "Apri" che mostra il pacchetto (con [still] = "riduci animazioni").
Widget _app({
  int overall = 82,
  int? previous,
  CardSpecial? special,
  int bonus = 0,
  bool still = false,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: still),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showWalkout(
            context,
            member: _rossi.copyWith(overall: overall),
            stats: _stats,
            previousOverall: previous,
            special: special,
            bonus: bonus,
          ),
          child: const Text('Apri'),
        ),
      ),
    ),
  ),
);

/// Apre la pagina del pacchetto e aspetta che la bustina sia arrivata.
Future<void> _showPack(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.tap(find.text('Apri'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
}

/// Le vibrazioni chieste dall'app, per tipo (light, medium, heavy, selection).
List<String> _recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      haptics.add(switch (call.arguments) {
        'HapticFeedbackType.lightImpact' => 'light',
        'HapticFeedbackType.mediumImpact' => 'medium',
        'HapticFeedbackType.heavyImpact' => 'heavy',
        'HapticFeedbackType.selectionClick' => 'selection',
        _ => 'vibrate',
      });
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return haptics;
}

/// Avanza di [total] un fotogramma ogni 50 ms (per seguire l'overall che sale).
Future<void> _frames(WidgetTester tester, Duration total) async {
  for (
    var t = Duration.zero;
    t < total;
    t += const Duration(milliseconds: 50)
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

int _count(List<String> haptics, String kind) =>
    haptics.where((h) => h == kind).length;

void main() {
  testWidgets('Pacchetto: aspetta il tocco, poi strappo, walkout e carta', (
    tester,
  ) async {
    await _showPack(tester, _app());
    expect(find.text('BENVENUTO'), findsOneWidget);
    expect(find.text('Tocca per aprire'), findsOneWidget);
    // Senza tocco il pacchetto resta chiuso, anche a lungo.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Tocca per aprire'), findsOneWidget);
    expect(find.text('NUOVO ACQUISTO!'), findsNothing);

    await tester.tap(find.text('Tocca per aprire'));
    await tester.pump();
    expect(find.text('Tocca per aprire'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('ATT'), findsOneWidget); // ruolo rivelato
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('NUOVO ACQUISTO!'), findsOneWidget);
    expect(find.text('Benvenuto nel MILANAC Pro Club.'), findsOneWidget);
    // La carta ferma è viva (riflesso e inclinazione).
    expect(find.byType(LiveCard), findsOneWidget);

    // Un tocco a carta ferma non chiude (serve a inclinarla): si esce con Continua.
    await tester.tapAt(const Offset(30, 400));
    await tester.pumpAndSettle();
    expect(find.byType(WalkoutPage), findsOneWidget);
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    expect(find.byType(WalkoutPage), findsNothing);
    expect(find.text('Apri'), findsOneWidget);
  });

  testWidgets('Pacchetto: tirato poco torna giù, tirato su si apre', (
    tester,
  ) async {
    await _showPack(tester, _app());
    await tester.drag(find.byType(OpeningPack), const Offset(0, -60));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tocca per aprire'), findsOneWidget);
    expect(
      tester.widget<OpeningPack>(find.byType(OpeningPack)).pull,
      0,
      reason: 'lasciato presto, il pacchetto torna come prima',
    );

    await tester.drag(find.byType(OpeningPack), const Offset(0, -220));
    await tester.pump();
    expect(find.text('Tocca per aprire'), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('NUOVO ACQUISTO!'), findsOneWidget);
    expect(find.text('Continua'), findsOneWidget);
  });

  testWidgets(
    "Overall salito: l'overall di prima sale sulla carta, con le vibrazioni",
    (tester) async {
      final haptics = _recordHaptics(tester);
      await _showPack(tester, _app(overall: 76, previous: 72));
      expect(find.text('POTENZIAMENTO'), findsOneWidget);
      await tester.tap(find.text('Tocca per aprire'));
      await tester.pump();
      // La carta appena ferma ha ancora l'overall di prima…
      await tester.pump(const Duration(milliseconds: 6400));
      expect(find.text('72'), findsOneWidget);
      expect(find.text('OVERALL +4'), findsOneWidget);
      // …che sale punto per punto fino al nuovo.
      await _frames(tester, const Duration(milliseconds: 1700));
      expect(find.text('76'), findsOneWidget);
      expect(find.text('72'), findsNothing);
      expect(find.text("L'overall sale a 76."), findsOneWidget);
      // Una all'apertura, tre colpetti mentre trema, lo strappo, le tre rivelazioni,
      // la carta che gira e si ferma, un tic per ognuno dei quattro punti.
      expect(_count(haptics, 'light'), 2);
      expect(_count(haptics, 'medium'), 3);
      expect(_count(haptics, 'heavy'), 2);
      expect(_count(haptics, 'selection'), 3 + 4);
    },
  );

  testWidgets('Carta speciale: il bonus si somma quando la carta si ferma', (
    tester,
  ) async {
    await _showPack(tester, _app(special: CardSpecial.neroOro, bonus: 5));
    expect(find.text('SPECIALE'), findsOneWidget);
    await tester.tap(find.text('Tocca per aprire'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 6400));
    expect(find.text('82'), findsOneWidget);
    expect(find.text('+5'), findsNothing);
    await _frames(tester, const Duration(milliseconds: 1700));
    expect(find.text('CARTA DELLA SETTIMANA'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
  });

  testWidgets(
    'Salta: dal pacchetto chiuso alla carta, senza raffica di vibrazioni',
    (tester) async {
      final haptics = _recordHaptics(tester);
      await _showPack(tester, _app(special: CardSpecial.blu, bonus: 3));
      await tester.tap(find.text('Salta'));
      await tester.pump();
      expect(find.text('BLU ELETTRICO'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('Continua'), findsOneWidget);
      expect(find.text('Salta'), findsNothing);
      expect(haptics, ['light']);
      await tester.tap(find.text('Continua'));
      await tester.pumpAndSettle();
      expect(find.byType(WalkoutPage), findsNothing);
    },
  );

  testWidgets('Un tocco durante il walkout salta alla carta ferma', (
    tester,
  ) async {
    await _showPack(tester, _app(overall: 76, previous: 72));
    await tester.tap(find.text('Tocca per aprire'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Continua'), findsNothing);
    await tester.tapAt(const Offset(30, 400));
    await tester.pump();
    expect(find.text('Continua'), findsOneWidget);
    expect(find.text('76'), findsOneWidget);
  });

  testWidgets('Con "riduci animazioni" il pacchetto aspetta fermo', (
    tester,
  ) async {
    await _showPack(tester, _app(still: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Tocca per aprire'), findsOneWidget);
  });

  test('Lo strappo divide la bustina in due parti che combaciano', () {
    const size = Size(220, 330);
    final flap = const PackTearClipper(top: true).getClip(size);
    final body = const PackTearClipper(top: false).getClip(size);
    final seam = size.height * PackArt.seam;
    expect(flap.contains(Offset(110, seam - 10)), isTrue);
    expect(flap.contains(Offset(110, seam + 10)), isFalse);
    expect(body.contains(Offset(110, seam + 10)), isTrue);
    expect(body.contains(Offset(110, seam - 10)), isFalse);
  });

  test(
    'Effetti: scintille, razzi, sfondo e luce dello strappo si disegnano',
    () {
      const size = Size(360, 780);
      void draw(CustomPainter painter) {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), size);
        recorder.endRecording().dispose();
      }

      for (final s in [-1.0, -.2, 0.0, .3, 1.0, 2.0]) {
        draw(
          BurstPainter([
            Burst(
              at: const Offset(.5, .3),
              seconds: s,
              color: Colors.amber,
              ring: true,
              launch: const Offset(.5, .86),
            ),
          ]),
        );
      }
      for (final lights in [0.0, .5, 1.0]) {
        draw(
          WalkoutBackdropPainter(
            color: Colors.amber,
            glow: .5,
            beams: lights,
            spin: 1,
            twinkle: 12,
            lights: lights,
          ),
        );
      }
      draw(const SeamLeakPainter(leak: .6, color: Colors.blue));

      const a = Burst(at: Offset(.5, .5), seconds: .2, color: Colors.amber);
      const same = Burst(at: Offset(.5, .5), seconds: .2, color: Colors.amber);
      const later = Burst(
        at: Offset(.5, .5),
        seconds: .25,
        color: Colors.amber,
      );
      expect(
        const BurstPainter([a]).shouldRepaint(const BurstPainter([same])),
        isFalse,
      );
      expect(
        const BurstPainter([a]).shouldRepaint(const BurstPainter([later])),
        isTrue,
      );
    },
  );
}
