import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/calendario/club_event.dart';
import 'package:milanac/features/auth/gate_ui.dart';
import 'package:milanac/features/calendario/events_repository.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/presenze/evening.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/main.dart';

import 'direttivo_poteri_test.dart' show openEditor, openRoster, tapInSheet;
import 'helpers.dart';
import 'home_test.dart' show italyAt, startAppAt;
import 'labeled_field.dart';
import 'presenze_test.dart' show dayTile;

/// Il regolamento: serate dal lunedì al venerdì (21:30-23:30), in party trenta minuti
/// prima della partita, ruoli del Direttivo come nell'organigramma.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('it');
    // Barlow vero (nei test il carattere predefinito è un segnaposto più largo): le
    // etichette dei ruoli si misurano come sul telefono.
    final barlow = FontLoader(bodyFont);
    for (final w in ['400', '500', '600', '700']) {
      barlow.addFont(rootBundle.load('assets/fonts/Barlow-$w.ttf'));
    }
    await barlow.load();
  });

  // Novembre 2026: venerdì 6, sabato 7, domenica 8, lunedì 9.
  ClubEvent event(String id, EventType type, DateTime startsAt, {Team? team}) =>
      ClubEvent(
        id: id,
        type: type,
        title: type.label,
        startsAt: startsAt,
        team: team,
      );

  /// Telefono stretto: 320 dp (o 360) di larghezza.
  Future<void> narrow(WidgetTester tester, [double width = 320]) async {
    tester.view.physicalSize = Size(width * 3, 2080);
    await tester.pumpAndSettle();
  }

  test(
    'serate dal lunedì al venerdì: sabato e domenica solo con un evento',
    () {
      final venerdi = DateTime(2026, 11, 6);
      final sabato = DateTime(2026, 11, 7);
      final domenica = DateTime(2026, 11, 8);
      expect(eveningHours, '21:30–23:30');
      expect(isClubWeekday(venerdi), isTrue);
      expect(isClubWeekday(sabato), isFalse);
      expect(isClubWeekday(domenica), isFalse);

      expect(eveningEvent(const [], venerdi)!.type, EventType.allenamento);
      expect(eveningEvent(const [], sabato), isNull);
      expect(eveningEvent(const [], domenica), isNull);

      final riunione = event(
        'r',
        EventType.riunione,
        DateTime.utc(2026, 11, 7, 21),
      );
      final torneoFuturo = event(
        't',
        EventType.torneo,
        DateTime.utc(2026, 11, 8, 21, 30),
        team: Team.futuro,
      );
      expect(
        eveningEvent([riunione], sabato),
        isNull,
        reason: 'le riunioni non chiedono presenze',
      );
      expect(eveningEvent([torneoFuturo], domenica)!.id, 't');
      expect(
        eveningEvent([torneoFuturo], domenica, teams: {Team.milanac}),
        isNull,
        reason: 'la partita del Futuro non è una serata del MILANAC',
      );

      // La prossima serata: dal sabato il lunedì, o prima se c'è una partita.
      final lunedi = nextEvening(const [], sabato);
      expect(lunedi.day, DateTime(2026, 11, 9));
      expect(lunedi.event.type, EventType.allenamento);
      expect(nextEvening([torneoFuturo], sabato).day, domenica);
      expect(
        nextEvening([torneoFuturo], sabato, teams: {Team.milanac}).day,
        DateTime(2026, 11, 9),
      );
      expect(nextEvening(const [], venerdi).day, DateTime(2026, 11, 9));

      // Chi ha la serata: nel fine settimana solo chi gioca nella squadra dell'evento.
      final milan = Member(
        id: 'm',
        displayName: 'Milan',
        role: ClubRole.giocatore,
        joinedAt: DateTime(2026),
      );
      final futuro = Member(
        id: 'f',
        displayName: 'Futuro',
        role: ClubRole.giocatore,
        teams: const {Team.futuro},
        joinedAt: DateTime(2026),
      );
      expect(playingTonight([milan, futuro], const [], venerdi), hasLength(2));
      expect(playingTonight([milan, futuro], const [], sabato), isEmpty);
      expect(
        playingTonight([milan, futuro], [torneoFuturo], domenica).single.id,
        'f',
      );
    },
  );

  testWidgets('Home il sabato senza eventi: riposo e la prossima serata, anche '
      'a 320 dp', (tester) async {
    await startAppAt(tester, italyAt(2026, 11, 7, 17));
    await narrow(tester);
    expect(find.text('STASERA · MILANAC'), findsOneWidget);
    expect(find.text('RIPOSO'), findsOneWidget);
    expect(
      find.textContaining('dal lunedì al venerdì, 21:30–23:30'),
      findsOneWidget,
    );
    // Nessuna risposta da dare: la serata non c'è.
    expect(find.widgetWithText(OutlinedButton, 'Presente'), findsNothing);
    expect(find.textContaining('Rispondi entro'), findsNothing);
    // La demo ha la partita di lunedì 9: è la prossima serata, dove si risponde già.
    final next = find.text(
      'Prossima serata: Lunedì 9 novembre · Partita ufficiale 21:30',
    );
    expect(next, findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('LUNEDÌ 9 NOVEMBRE · MILANAC'), findsOneWidget);
    expect(find.text('PARTITA UFFICIALE 21:30'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Presente'), findsWidgets);
  });

  testWidgets('Home la domenica con una partita: il Match Day c\'è, con il '
      'party trenta minuti prima', (tester) async {
    final now = italyAt(2026, 11, 8, 17);
    final container = await startAppAt(tester, now);
    await container
        .read(eventsRepositoryProvider)
        .save(
          ClubEvent(
            id: '',
            type: EventType.torneo,
            title: 'Coppa – Ottavi vs Lupi Grigi',
            startsAt: DateTime.utc(2026, 11, 8, 21, 30),
          ),
        );
    await tester.pumpAndSettle();
    await narrow(tester, 360);
    expect(find.text('MATCH DAY · MILANAC'), findsOneWidget);
    expect(find.text('RIPOSO'), findsNothing);
    await tester.ensureVisible(
      find.text('Promemoria: in party alle 21:00, in lobby alle 21:20'),
    );
    expect(
      find.text('Promemoria: in party alle 21:00, in lobby alle 21:20'),
      findsOneWidget,
    );
  });

  testWidgets('Presenze il sabato: riposo, niente pulsanti, il giorno è più '
      'chiaro', (tester) async {
    await startAppAt(tester, italyAt(2026, 11, 7, 17));
    await narrow(tester);
    await goToSection(tester, 'Presenze');
    expect(dayTile('Sabato 7, oggi, riposo'), findsOneWidget);
    expect(dayTile('Venerdì 6'), findsOneWidget);
    expect(dayTile('Venerdì 6, riposo'), findsNothing);
    expect(find.text('OGGI · MILANAC'), findsOneWidget);
    expect(find.text('RIPOSO'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Presente'), findsNothing);
    expect(find.text('Chi c\'è stasera'), findsNothing);
    // Il lunedì dopo c'è la partita.
    await tester.tap(find.byTooltip('Settimana successiva'));
    await tester.pumpAndSettle();
    await tester.tap(dayTile('Lunedì 9, partita'));
    await tester.pumpAndSettle();
    expect(find.text('PARTITA UFFICIALE 21:30'), findsOneWidget);
  });

  testWidgets('Sala Direttivo il sabato: niente serata da controllare', (
    tester,
  ) async {
    await startAppAt(tester, italyAt(2026, 11, 7, 18, 31));
    await narrow(tester);
    await goToSection(tester, 'Sala Direttivo');
    expect(find.text('Stasera niente serata (lunedì-venerdì)'), findsOneWidget);
    await tester.tap(find.text('Senza risposta stasera'));
    await tester.pumpAndSettle();
    expect(find.text('PRESENZE DI STASERA'), findsOneWidget);
    expect(find.textContaining('stasera niente serata'), findsOneWidget);
    expect(find.text('Luca Bianchi'), findsNothing);
  });

  testWidgets('Sala Direttivo la domenica con una partita del Futuro: solo chi '
      'gioca nel Futuro', (tester) async {
    final container = await startAppAt(tester, italyAt(2026, 11, 8, 18, 31));
    await container
        .read(eventsRepositoryProvider)
        .save(
          ClubEvent(
            id: '',
            type: EventType.amichevole,
            title: 'Amichevole vs Orsi',
            team: Team.futuro,
            startsAt: DateTime.utc(2026, 11, 8, 21, 30),
          ),
        );
    await tester.pumpAndSettle();
    await goToSection(tester, 'Sala Direttivo');
    await tester.tap(find.text('Senza risposta stasera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('risposte chiuse alle 18:30'), findsOneWidget);
    // La demo: uno gioca in tutte e due le squadre, uno solo nel Futuro.
    expect(find.text('SENZA RISPOSTA · 2'), findsOneWidget);
    expect(find.text('Andrea Neri'), findsOneWidget);
    expect(find.text('Paolo Verdi'), findsOneWidget);
    expect(find.text('Luca Bianchi'), findsNothing);
  });

  test('ruoli del Direttivo: l\'organigramma del regolamento', () {
    expect(DirettivoRole.values.map((r) => r.name), [
      'presidente',
      'fondatore',
      'capitano',
      'vicecapitano',
      'comunicazione',
      'tecnico',
      'reclutamento',
      'tornei',
      'presenze',
      'it',
    ]);
    expect(DirettivoRole.vicecapitano.label, 'Vice-capitano');
    expect(
      DirettivoRole.comunicazione.label,
      'Resp. Comunicazioni e Marketing',
    );
    expect(DirettivoRole.tornei.label, 'Resp. Tornei e Amichevoli');
    // I nomi di prima non esistono più (il database li ha già tradotti).
    expect(DirettivoRole.parseList(['gestore', 'tecnico', 'it']), [
      DirettivoRole.tecnico,
      DirettivoRole.it,
    ]);
    const p = Profile(
      id: 'x',
      displayName: 'X',
      role: ClubRole.direttivo,
      direttivoRoles: [DirettivoRole.presidente, DirettivoRole.presenze],
    );
    expect(p.roleLabel, 'Direttivo · Presidente, Resp. Presenze');
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('Rosa e squadre a ${width.toInt()} dp: i ruoli lunghi vanno a '
        'capo senza uscire dallo schermo', (tester) async {
      final repo = await openRoster(tester);
      await narrow(tester, width);
      await openEditor(tester, 'Marco Rossi');
      await tester.tap(find.text('Direttivo').last);
      await tester.pumpAndSettle();
      for (final r in DirettivoRole.values) {
        final chip = find.widgetWithText(FilterChip, r.label);
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        final box = tester.getRect(chip);
        expect(box.left, greaterThanOrEqualTo(0), reason: r.label);
        expect(box.right, lessThanOrEqualTo(width), reason: r.label);
        // L'etichetta si legge intera: non sfuma a metà né va oltre lo spazio.
        final text = tester.renderObject<RenderParagraph>(
          find.descendant(of: chip, matching: find.text(r.label)),
        );
        expect(
          text.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(text.size.width + .5),
          reason: r.label,
        );
        expect(text.didExceedMaxLines, isFalse, reason: r.label);
      }
      await tapInSheet(
        tester,
        find.widgetWithText(FilterChip, 'Resp. Tornei e Amichevoli'),
      );
      await tapInSheet(
        tester,
        find.widgetWithText(FilterChip, 'Vice-capitano'),
      );
      await tapInSheet(tester, find.text('Salva'));
      final p2 = (await repo.watchAll().first).firstWhere((m) => m.id == 'p2');
      expect(p2.direttivoRoles, [
        DirettivoRole.vicecapitano,
        DirettivoRole.tornei,
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Registrazione come Direttivo a 320 dp: i dieci ruoli in pillole che '
    'vanno a capo, nell\'ordine dell\'organigramma',
    (tester) async {
      tester.view.physicalSize = const Size(960, 2080);
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
      container.read(routerProvider).go('/registrazione');
      await tester.pumpAndSettle();
      await tester.enterText(labeledField('Nome'), 'Mario');
      await tester.enterText(labeledField('Cognome'), 'Rossi');
      await tester.enterText(labeledField('Anno di nascita'), '1995');
      await tester.enterText(
        labeledField('Nome sulla maglia e sulla carta'),
        'Rossi',
      );
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      expect(find.text('Passo 2 di 3'), findsOneWidget);
      await tester.tap(find.text('Direttivo'));
      await tester.pumpAndSettle();
      Rect? previous;
      for (final r in DirettivoRole.values) {
        final pill = find.widgetWithText(ChoicePill, r.label);
        await tester.ensureVisible(pill);
        await tester.pumpAndSettle();
        final box = tester.getRect(pill);
        expect(box.left, greaterThanOrEqualTo(0), reason: r.label);
        expect(box.right, lessThanOrEqualTo(320), reason: r.label);
        final text = tester.renderObject<RenderParagraph>(
          find.descendant(of: pill, matching: find.text(r.label)),
        );
        expect(text.didExceedMaxLines, isFalse, reason: r.label);
        // Le pillole stanno in fila: le corte una accanto all'altra.
        if (previous != null && r == DirettivoRole.fondatore) {
          expect(
            box.top,
            previous.top,
            reason: 'Presidente e Fondatore in fila',
          );
        }
        previous = box;
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('La mia carta a 320 dp: i ruoli nel Direttivo per intero', (
    tester,
  ) async {
    await startAppAt(tester, italyAt(2026, 11, 6, 17));
    await narrow(tester);
    await goToSection(tester, 'La mia carta');
    final role = find.text('Direttivo · Capitano, Resp. Presenze');
    await tester.scrollUntilVisible(
      role,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(role, findsOneWidget);
    expect(tester.getRect(role).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });
}
