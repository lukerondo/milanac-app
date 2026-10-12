import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/privacy/privacy_page.dart';
import 'package:milanac/main.dart';

import 'helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('senza parametri Firebase le notifiche sono disattivate', () {
    expect(FirebaseConfig.current, isNull);
  });

  testWidgets('Privacy raggiungibile dalle Impostazioni', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(introDoneProvider.notifier).complete();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MilanacApp(),
      ),
    );
    await tester.pumpAndSettle();
    // La Privacy sta nelle Impostazioni (dal profilo, foto in alto a destra).
    await goToSection(tester, 'Impostazioni');
    await tester.scrollUntilVisible(
      find.text('Privacy'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Informativa sulla privacy'), findsOneWidget);
    expect(find.textContaining('{{EMAIL}}'), findsNothing);
    // Senza CONTACT_EMAIL niente indirizzi inventati: si scrive al Direttivo in chat.
    expect(find.textContaining('da-configurare'), findsNothing);
    expect(
      find.textContaining('scrivi al Direttivo nella chat del club'),
      findsOneWidget,
    );
    // I percorsi di oggi (Profilo → Impostazioni), non il vecchio menu laterale.
    expect(find.textContaining('menu laterale'), findsNothing);
    expect(find.textContaining('ingranaggio'), findsNothing);
    expect(
      find.textContaining('Profilo (la tua foto in alto a destra)'),
      findsOneWidget,
    );
  });

  test(
    'contatto dell\'informativa: l\'email del club o il Direttivo in chat',
    () {
      expect(privacyContact(''), 'scrivi al Direttivo nella chat del club.');
      expect(privacyContact('  '), 'scrivi al Direttivo nella chat del club.');
      expect(privacyContact('club@milanac.it'), 'club@milanac.it');
    },
  );

  test('l\'informativa elenca davvero i dati raccolti', () {
    final text = File('assets/legal/privacy.md').readAsStringSync();
    for (final words in [
      'indirizzo email',
      'nome, cognome e anno di nascita',
      'li vede solo il Direttivo',
      'nome sulla carta',
      'volto',
      'foto del profilo',
      'motto',
      'ruolo',
      'piattaforma',
      'Presenze',
      'messaggi vocali',
      '60 giorni',
      'replay',
      '3 giorni',
      'Agora',
      'non viene registrata',
      'Firebase',
    ]) {
      expect(text, contains(words), reason: words);
    }
    expect(text, isNot(contains('menu laterale')));
    expect(text, isNot(contains('ingranaggio')));
  });
}
