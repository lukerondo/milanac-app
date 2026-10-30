import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/features/carta/archetypes.dart';
import 'package:milanac/features/carta/fut_card.dart';
import 'package:milanac/features/carta/playstyle_ui.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/features/rosa/rosa_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'helpers.dart';
import 'home_test.dart' show startAppAt, todayAt;

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test(
    'Archetipi: riconosciuti dallo stile di gioco, anche scritto a mano',
    () {
      expect(archetypeOf('Finalizzatore')?.icon, Icons.gps_fixed_rounded);
      expect(archetypeOf('  box TO box ')?.name, 'Box to box');
      expect(archetypeOf('Bomber di razza'), isNull);
      expect(archetypeOf(null), isNull);
      // Ogni reparto ha i suoi, e i vecchi stili proposti sono ancora tutti archetipi.
      for (final area in ArchetypeArea.values) {
        expect(archetypes.where((a) => a.area == area), isNotEmpty);
      }
      for (final old in [
        'Finalizzatore',
        'Regista',
        'Box to box',
        'Muro',
        'Velocista',
        'Fantasista',
        'Mediano',
        'Saracinesca',
      ]) {
        expect(archetypeOf(old), isNotNull, reason: old);
      }
    },
  );

  test(
    'PlayStyle: prima i "+", codici sconosciuti saltati, letti e salvati',
    () {
      final chosen = chosenPlayStyles([
        'scatto',
        'tiro_potente+',
        'mossa_del_futuro',
        'colpo_di_testa+',
      ]);
      expect(
        [for (final c in chosen) (c.style.name, c.plus)],
        [
          ('Tiro potente', true),
          ('Colpo di testa', true),
          ('Scatto bruciante', false),
        ],
      );
      // Codici unici nel catalogo.
      expect(
        playStyleCatalog.map((p) => p.code).toSet(),
        hasLength(playStyleCatalog.length),
      );

      final m = Member.fromMap({
        'id': 'x',
        'display_name': 'Marco Rossi',
        'joined_at': '2025-02-03',
        'club_role': 'giocatore',
        'play_styles': ['tiro_potente+', 'scatto'],
      });
      expect(m.playStyles, ['tiro_potente+', 'scatto']);
      expect(m.cardMap()['play_styles'], ['tiro_potente+', 'scatto']);
      // Server prima della 0028: nessun PlayStyle.
      final old = Member.fromMap({
        'id': 'y',
        'display_name': 'Luca Bianchi',
        'joined_at': '2025-02-03',
        'club_role': 'giocatore',
      });
      expect(old.playStyles, isEmpty);
      expect(m.copyWith(overall: 80).playStyles, m.playStyles);
    },
  );

  test(
    'Server senza la colonna dei PlayStyle: la carta si salva lo stesso',
    () async {
      final sent = <Map<String, dynamic>>[];
      Future<void> update(Map<String, dynamic> fields) async {
        sent.add(fields);
        if (fields.containsKey('play_styles')) {
          throw PostgrestException(
            message:
                "Could not find the 'play_styles' column of 'profiles' in the "
                'schema cache',
            code: 'PGRST204',
          );
        }
      }

      final fields = {
        'play_style': 'Regista',
        'play_styles': ['tiro_a_giro'],
      };
      expect(await updateWithoutMissing(fields, update), {'play_styles'});
      expect(sent, hasLength(2));
      expect(sent.last, {'play_style': 'Regista'});
      // Poi non la si manda più.
      sent.clear();
      expect(
        await updateWithoutMissing(fields, update, skip: {'play_styles'}),
        {'play_styles'},
      );
      expect(sent.single, {'play_style': 'Regista'});
      // Con la colonna tutto in un colpo.
      sent.clear();
      expect(
        await updateWithoutMissing(fields, (f) async => sent.add(f)),
        isEmpty,
      );
      expect(sent.single, fields);
      // Gli altri errori arrivano a chi salva.
      await expectLater(
        updateWithoutMissing(
          fields,
          (_) async => throw PostgrestException(message: 'no', code: '42501'),
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test('Server senza le statistiche FUT (migrazione 0032): si tolgono una alla '
      'volta le colonne che mancano, il resto si salva', () async {
    final sent = <Map<String, dynamic>>[];
    Future<void> update(Map<String, dynamic> fields) async {
      sent.add(fields);
      for (final c in ['fut_stats', 'play_styles']) {
        if (fields.containsKey(c)) {
          throw PostgrestException(
            message:
                "Could not find the '$c' column of 'profiles' in the "
                'schema cache',
            code: 'PGRST204',
          );
        }
      }
    }

    final fields = {
      'play_style': 'Regista',
      'play_styles': ['tiro_a_giro'],
      'fut_stats': {'pac': 80},
    };
    expect(await updateWithoutMissing(fields, update), {
      'fut_stats',
      'play_styles',
    });
    expect(sent, hasLength(3));
    expect(sent.last, {'play_style': 'Regista'});
    // Una colonna sconosciuta che manca non si toglie: l'errore arriva a chi salva.
    await expectLater(
      updateWithoutMissing(
        {'gamertag': 'x'},
        (_) async => throw PostgrestException(
          message: "Could not find the 'gamertag' column",
          code: 'PGRST204',
        ),
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  testWidgets('Editor della carta: archetipo e PlayStyle (un tocco, due per '
      'il "+", tre per toglierlo), con i limiti', (tester) async {
    await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'La mia carta');
    await tester.ensureVisible(find.text('Modifica la mia carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifica la mia carta'));
    await tester.pumpAndSettle();

    // Archetipo: un tocco lo sceglie e dice cosa fa.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Regista'));
    await tester.pumpAndSettle();
    expect(find.text('Detta i tempi e accende il gioco.'), findsOneWidget);

    Future<void> tapStyle(String name) async {
      final chip = find.text(name);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    // Due tocchi: PlayStyle+. Il terzo "+" non c'è posto: si toglie.
    await tapStyle('Tiro a giro');
    await tapStyle('Tiro a giro');
    expect(find.text('Tiro a giro+'), findsOneWidget);
    await tapStyle('Filtrante');
    await tapStyle('Filtrante');
    await tapStyle('Tecnico');
    await tapStyle('Tecnico');
    expect(find.textContaining('Al massimo 2 PlayStyle+'), findsOneWidget);
    expect(find.text('Tecnico+'), findsNothing);
    // Fino a 6 in tutto.
    for (final name in [
      'Tecnico',
      'Rapido',
      'Instancabile',
      'Anticipo',
      'Estro',
    ]) {
      await tapStyle(name);
    }
    expect(find.textContaining('Al massimo 6 PlayStyle'), findsOneWidget);
    expect(find.text('6/6 · 2/2 in oro'), findsOneWidget);

    await tester.ensureVisible(find.text('Salva la carta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva la carta'));
    await tester.pumpAndSettle();

    // Sulla carta i due PlayStyle+ nei rombi d'oro; sotto, archetipo e PlayStyle.
    await tester.scrollUntilVisible(
      find.byType(FutCard),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byType(FutCard),
        matching: find.byType(PlayStyleBadge),
      ),
      findsNWidgets(2),
    );
    await tester.scrollUntilVisible(
      find.text('PLAYSTYLE'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ARCHETIPO'), findsOneWidget);
    expect(find.text('Filtrante+'), findsOneWidget);
    expect(find.text('Anticipo'), findsOneWidget);
  });

  testWidgets('La carta di Rossi mostra i suoi PlayStyle+', (tester) async {
    await startAppAt(tester, todayAt(17));
    await goToSection(tester, 'Rosa completa');
    await tester.tap(find.text('MARCO ROSSI'));
    await tester.pumpAndSettle();
    final badges = tester.widgetList<PlayStyleBadge>(
      find.descendant(
        of: find.byType(FutCard),
        matching: find.byType(PlayStyleBadge),
      ),
    );
    expect(
      [for (final b in badges) b.style.name],
      ['Tiro potente', 'Colpo di testa'],
    );
    // La demo guarda da Direttivo: può modificare la carta di un compagno.
    expect(find.text('Modifica carta'), findsOneWidget);
  });
}
