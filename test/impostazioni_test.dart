import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/auth/auth_repository.dart';
import 'package:milanac/core/auth/notify_prefs.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/local_flags.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/impostazioni/impostazioni_page.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/member_photo.dart';

import 'helpers.dart';
import 'labeled_field.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('bandiera dal codice ISO', () {
    expect(flagEmoji('IT'), '🇮🇹');
    expect(flagEmoji('es'), '🇪🇸');
  });

  Future<ProviderContainer> startApp(WidgetTester tester) async {
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
    return container;
  }

  testWidgets(
    'Impostazioni: volto e dati personali, poi la bandiera sulla carta',
    (tester) async {
      await startApp(tester);
      await goToSection(tester, 'Impostazioni');
      expect(find.text('IMPOSTAZIONI'), findsOneWidget);
      for (final group in ['PROFILO', 'NOTIFICHE', 'ASPETTO', 'ACCOUNT']) {
        expect(find.text(group), findsOneWidget);
      }

      // Il volto si cambia in una pagina dedicata.
      await tester.tap(find.text('Il tuo volto'));
      await tester.pumpAndSettle();
      expect(find.text('IL TUO VOLTO'), findsOneWidget);
      await tester.tap(find.text('A caso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SALVA'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Volto aggiornato'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Dati personali: pagina a parte, poi si torna alle impostazioni.
      await tester.tap(find.text('Dati personali'));
      await tester.pumpAndSettle();
      expect(find.text('DATI PERSONALI'), findsOneWidget);
      await tester.ensureVisible(labeledField('Città'));
      await tester.enterText(labeledField('Città'), 'Milano');
      await tester.ensureVisible(find.text('Nazionalità'));
      await tester.tap(find.text('Non indicata'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🇮🇹  Italia').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sinistro'));
      await tester.tap(find.text('Sinistro'));
      await tester.tap(find.text('Salva i dati'));
      await tester.pumpAndSettle();
      expect(find.text('Dati salvati.'), findsOneWidget);
      expect(find.text('IMPOSTAZIONI'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await goToSection(tester, 'La mia carta');
      expect(find.text('🇮🇹'), findsOneWidget);
    },
  );

  testWidgets(
    'Aspetto: chiaro, scuro o automatico (come il telefono), salvato sul '
    'telefono',
    (tester) async {
      final container = await startApp(tester);
      await goToSection(tester, 'Impostazioni');
      Brightness brightness() =>
          Theme.of(tester.element(find.text('ASPETTO'))).brightness;
      expect(brightness(), Brightness.dark);

      await tester.ensureVisible(find.text('Chiaro'));
      await tester.tap(find.text('Chiaro'));
      await tester.pumpAndSettle();
      expect(container.read(appearanceProvider), Appearance.chiaro);
      expect(brightness(), Brightness.light);
      expect(
        await container.read(localFlagsProvider).getString('aspetto'),
        'chiaro',
      );

      expect(
        find.text('Automatico segue il tema chiaro o scuro del telefono.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Automatico'));
      await tester.pumpAndSettle();
      expect(container.read(appearanceProvider), Appearance.sistema);
      await tester.tap(find.text('Scuro'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
    },
  );

  testWidgets('Notifiche: si spegne una categoria e resta spenta', (
    tester,
  ) async {
    final container = await startApp(tester);
    await goToSection(tester, 'Impostazioni');
    SwitchListTile toggle(String label) =>
        tester.widget(find.widgetWithText(SwitchListTile, label));
    expect(toggle('Notizie e aggiornamenti').value, isTrue);
    expect(
      find.text(
        'Formazione, risultati, carte speciali, regolamento e avvisi del '
        'Direttivo arrivano sempre.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Notizie e aggiornamenti'));
    await tester.pumpAndSettle();
    expect(toggle('Notizie e aggiornamenti').value, isFalse);
    expect(toggle('Presenze e promemoria').value, isTrue);
    final prefs = container.read(profileProvider).value!.notifyPrefs;
    expect(prefs.toJson(), {'presenze': true, 'chat': true, 'notizie': false});

    // Riaperte le impostazioni, la scelta c'è ancora.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await goToSection(tester, 'Impostazioni');
    expect(toggle('Notizie e aggiornamenti').value, isFalse);
  });

  test('preferenze delle notifiche: chiave mancante (o colonna) = attiva', () {
    expect(NotifyPrefs.fromJson(null), const NotifyPrefs());
    final prefs = NotifyPrefs.fromJson({'chat': false, 'presenze': true});
    expect(prefs.isOn(NotifyCategory.chat), isFalse);
    expect(prefs.isOn(NotifyCategory.presenze), isTrue);
    expect(prefs.isOn(NotifyCategory.notizie), isTrue);
    final fromRow = Profile.fromMap({'id': 'u1', 'display_name': 'Mario'});
    expect(fromRow.notifyPrefs, const NotifyPrefs());
  });

  testWidgets('Dalla campanella: si apre con le notifiche in vista', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Future<double> notificheTop(String? section) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          child: MaterialApp(
            theme: buildTheme(),
            home: ImpostazioniPage(initialSection: section),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.text('NOTIFICHE')).dy;
    }

    final normal = await notificheTop(null);
    final fromBell = await notificheTop('notifiche');
    expect(fromBell, lessThan(normal - 100));
  });

  testWidgets(
    'Esci dall\'account: si aspetta l\'uscita sulla pagina, poi niente più ref',
    (tester) async {
      final auth = _SlowSignOut();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(auth)],
          child: MaterialApp(
            theme: buildTheme(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: LogoutTile()),
                  ),
                ),
                child: const Text('Impostazioni'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      // La pagina resta aperta con l'attesa sul pulsante; un secondo tocco non conta.
      await tester.tap(find.text('Esci dall\'account'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(LogoutTile));
      await tester.pump(const Duration(seconds: 1));
      expect(auth.calls, 1);
      expect(find.byType(LogoutTile), findsOneWidget);

      // Sessione chiusa: il router porta via la pagina mentre il server risponde ancora.
      Navigator.of(tester.element(find.byType(LogoutTile))).pop();
      await tester.pumpAndSettle();
      auth.done.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Impostazioni'), findsOneWidget);
    },
  );
}

/// Uscita lenta (rete): finisce quando lo decide il test.
class _SlowSignOut extends DemoAuthRepository {
  final done = Completer<void>();
  int calls = 0;

  @override
  Future<void> signOut() {
    calls++;
    return done.future;
  }
}
