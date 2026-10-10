import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/voce/voice_call.dart';
import 'package:milanac/features/voce/voice_models.dart';
import 'package:milanac/features/voce/voice_room_sheet.dart';

import 'helpers.dart';
import 'home_test.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('numero utente Agora: stabile, positivo e diverso tra profili', () {
    expect(agoraUidFor('demo'), agoraUidFor('demo'));
    expect(agoraUidFor('demo'), greaterThan(0));
    expect(agoraUidFor('p2'), isNot(agoraUidFor('p3')));
    expect(
      agoraUidFor('4f1c9a3e-0000-4000-8000-0000000000e1'),
      lessThan(1 << 31),
    );
  });

  testWidgets(
    'Stanza vocale: chi c\'è, entra, microfono, esci; apri una stanza nuova',
    (tester) async {
      final container = await startAppAt(tester, todayAt(17));
      await goToSection(tester, 'Chat');
      // Nell'elenco solo Milan AC ha le cuffie: la sua stanza è aperta.
      expect(find.byIcon(Icons.headset_mic_rounded), findsOneWidget);
      await tester.tap(find.text('Milan AC'));
      await tester.pumpAndSettle();
      expect(find.text('Stanza vocale aperta · 2 dentro'), findsOneWidget);

      await tester.tap(find.text('Entra'));
      await tester.pumpAndSettle();
      // Nel foglio: Marco (sta parlando), Luca (in muto) e io.
      expect(find.byType(VoiceRoomSheet), findsOneWidget);
      expect(find.text('Marco'), findsOneWidget);
      expect(find.text('Luca'), findsOneWidget);
      expect(find.text('Tu'), findsOneWidget);
      expect(find.text('3 dentro'), findsOneWidget);
      final call = container.read(voiceCallProvider);
      expect(call.phase, VoicePhase.inRoom);
      expect(call.speaking, {agoraUidFor('p2')});
      final mutedInSheet = find.descendant(
        of: find.byType(VoiceRoomSheet),
        matching: find.byIcon(Icons.mic_off_rounded),
      );
      expect(mutedInSheet, findsOneWidget);
      expect(find.text('Sei nella stanza vocale'), findsOneWidget);

      // Microfono spento: lo vedo su di me e sul pulsante.
      await tester.tap(find.text('Microfono'));
      await tester.pumpAndSettle();
      expect(container.read(voiceCallProvider).muted, isTrue);
      expect(mutedInSheet, findsNWidgets(3));

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.byType(VoiceRoomSheet), findsNothing);
      expect(container.read(voiceCallProvider).phase, VoicePhase.idle);
      expect(find.text('Stanza vocale aperta · 2 dentro'), findsOneWidget);

      // Generale: nessuna stanza. La apro io, esco e si chiude.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generale'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stanza vocale aperta'), findsNothing);
      await tester.tap(find.byTooltip('Stanza vocale'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nessuno è in stanza'), findsOneWidget);
      await tester.tap(find.text('Apri la stanza'));
      await tester.pumpAndSettle();
      expect(find.text('1 dentro'), findsOneWidget);
      expect(find.text('Tu'), findsOneWidget);
      expect(find.text('Sei nella stanza vocale'), findsOneWidget);
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.text('Sei nella stanza vocale'), findsNothing);
      expect(find.textContaining('Stanza vocale aperta'), findsNothing);
    },
  );
}
