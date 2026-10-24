import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/teams.dart';
import 'package:milanac/features/chat/chat_mentions.dart';
import 'package:milanac/features/chat/chat_reactions.dart';
import 'package:milanac/features/chat/chat_reads.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/chat/chat_typing.dart';
import 'package:milanac/features/rosa/member.dart';
import 'package:milanac/shared/link_text.dart';

import 'chat_test.dart' show openChannel, startChat;

Member _member(
  String id,
  String name, {
  ClubRole role = ClubRole.giocatore,
  Set<Team> teams = const {Team.milanac},
  bool active = true,
  String? gamertag,
}) => Member(
  id: id,
  displayName: name,
  firstName: name.split(' ').first,
  lastName: name.split(' ').last,
  role: role,
  teams: teams,
  active: active,
  gamertag: gamertag,
  joinedAt: DateTime(2026, 9, 1),
);

ChatMessage _message(String id, String author, DateTime at) =>
    ChatMessage(id: id, channelId: 'c', authorId: author, createdAt: at);

void main() {
  group('Menzioni', () {
    test('si riconosce la "@" che si sta scrivendo, non le mail', () {
      expect(mentionAt('@ma', 3), (start: 0, query: 'ma'));
      expect(mentionAt('Ciao @Marco R', 13), (start: 5, query: 'Marco R'));
      expect(mentionAt('Ciao @', 6), (start: 5, query: ''));
      expect(mentionAt('scrivi a mario@gmail.com', 24), isNull);
      expect(mentionAt('@Marco Rossi ', 13), isNull, reason: 'finita');
      expect(mentionAt('@a b c d', 8), isNull, reason: 'troppe parole');
      expect(mentionAt('@ciao\nsotto', 11), isNull);
      expect(mentionAt('niente', 6), isNull);
    });

    test(
      'candidati: nome sulla carta, nome, cognome o gamertag; non sé stessi',
      () {
        final team = [
          _member('p2', 'Marco Rossi', gamertag: 'Diavolo_9'),
          _member('p3', 'Luca Bianchi'),
          _member('me', 'Mario Verdi'),
        ];
        List<String> ids(String q) => [
          for (final m in mentionCandidates(q, team, me: 'me')) m.id,
        ];
        expect(ids('ma'), ['p2']);
        expect(ids('ROSSI'), ['p2']);
        expect(ids('diav'), ['p2']);
        expect(ids(''), ['p3', 'p2'], reason: 'tutti, in ordine di nome');
        expect(ids('zz'), isEmpty);
      },
    );

    test('nel messaggio vanno solo quelle ancora scritte', () {
      final picked = {'p2': 'Marco Rossi', 'p3': 'Luca Bianchi'};
      expect(mentionsIn('@Marco Rossi ci sei?', picked), ['p2']);
      expect(mentionsIn('nessuno', picked), isEmpty);
    });

    test('nel testo si evidenzia la più lunga', () {
      expect(splitMarks('Ciao @ROSSI JR!', ['@ROSSI', '@ROSSI JR']), [
        ('Ciao ', false),
        ('@ROSSI JR', true),
        ('!', false),
      ]);
      expect(splitMarks('niente', const []), [('niente', false)]);
    });
  });

  group('Spunte', () {
    test('chi vede il canale: Direttivo ovunque, squadre e attivi', () {
      final roster = [
        _member('d', 'Direttore Uno', role: ClubRole.direttivo, teams: {}),
        _member('a', 'Milan Uno'),
        _member('f', 'Futuro Uno', teams: {Team.futuro}),
        _member('x', 'Sospeso Uno', active: false),
        _member('p', 'Nuovo Uno', role: ClubRole.pending),
      ];
      List<String> who(Channel c) => [
        for (final m in channelAudience(c, roster)) m.id,
      ];
      const generale = Channel(id: 'g', slug: 'main', name: 'Generale');
      const milan = Channel(
        id: 'm',
        slug: 'milanac',
        name: 'Milan AC',
        team: 'milanac',
      );
      const sala = Channel(
        id: 's',
        slug: 'direttivo',
        name: 'Sala',
        direttivoOnly: true,
      );
      expect(who(generale), ['d', 'a', 'f']);
      expect(who(milan), ['d', 'a']);
      expect(who(sala), ['d']);
    });

    test(
      'ha letto chi è arrivato fino all\'ora del messaggio (non l\'autore)',
      () {
        final at = DateTime(2026, 10, 24, 21);
        final reads = {
          'me': at.add(const Duration(hours: 1)),
          'p2': at,
          'p3': at.subtract(const Duration(minutes: 1)),
        };
        expect(readersOf(_message('m', 'me', at), reads), {'p2'});
      },
    );
  });

  test('reazioni: dalla più data, a pari merito la prima arrivata', () {
    final t = DateTime(2026, 10, 24, 21);
    MessageReaction r(String user, String emoji, int minute) => MessageReaction(
      messageId: 'm',
      userId: user,
      emoji: emoji,
      at: t.add(Duration(minutes: minute)),
    );
    expect(
      reactionCounts([
        r('a', '🔥', 3),
        r('b', '👍', 1),
        r('c', '🔥', 2),
        r('d', '⚽', 0),
      ]),
      [('🔥', 2), ('⚽', 1), ('👍', 1)],
    );
  });

  test('"sta scrivendo": uno, due, tanti; il vocale si dice', () {
    final names = {
      'p2': _member('p2', 'Marco Rossi'),
      'p3': _member('p3', 'Luca Bianchi'),
    };
    expect(typingLabel({}, names), isNull);
    expect(typingLabel({'p2': TypingKind.testo}, names), 'Marco sta scrivendo');
    expect(
      typingLabel({'p3': TypingKind.vocale}, names),
      'Luca registra un vocale',
    );
    expect(
      typingLabel({'p3': TypingKind.testo, 'p2': TypingKind.testo}, names),
      'Marco e Luca stanno scrivendo',
    );
    expect(
      typingLabel({
        'p2': TypingKind.testo,
        'p3': TypingKind.testo,
        'x': TypingKind.testo,
      }, names),
      '3 persone stanno scrivendo',
    );
  });

  testWidgets(
    'Reazioni: pillole sotto la bolla, la propria dorata; un tocco la '
    'toglie, dal menu se ne sceglie un\'altra',
    (tester) async {
      final repo = DemoChatRepository();
      await startChat(tester, repo: repo);
      await openChannel(tester, 'Generale');
      // "Stasera tutti in lobby": 👍 di Luca e Andrea, 🔥 la mia.
      expect(find.bySemanticsLabel('👍, 2 reazioni'), findsOneWidget);
      final mine = find.bySemanticsLabel('🔥, 1 reazione, anche la tua');
      expect(mine, findsOneWidget);
      await tester.tap(mine);
      await tester.pumpAndSettle();
      expect(mine, findsNothing);

      // Dal menu del messaggio (pressione lunga): 😂.
      await tester.ensureVisible(find.text('Il gol di ieri 🔥'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Il gol di ieri 🔥'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Reagisci con 😂'));
      await tester.pumpAndSettle();
      // (Qui la bolla unisce le etichette: si cerca la parte della pillola.)
      expect(
        find.bySemanticsLabel(RegExp('😂, 1 reazione, anche la tua')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Spunte: una quando è arrivato, due dorate quando qualcuno l\'ha '
      'letto; "Info" dice chi', (tester) async {
    final repo = DemoChatRepository();
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    await tester.enterText(find.byType(TextField), 'Chi porta il pallone?');
    await tester.pump();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('inviato, non ancora letto')),
      findsOneWidget,
    );

    repo.readElsewhere(
      'c-main',
      'p2',
      DateTime.now().add(const Duration(minutes: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('letto da 1')), findsOneWidget);

    await tester.longPress(find.text('Chi porta il pallone?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info: chi l\'ha letto'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    expect(inSheet(find.text('Letto da (1)')), findsOneWidget);
    expect(inSheet(find.text('Marco Rossi')), findsOneWidget);
    expect(inSheet(find.textContaining('Non ancora letto da')), findsOneWidget);
  });

  testWidgets('Sta scrivendo: chi scrive compare sotto il nome del canale; '
      'scrivendo parte l\'avviso, inviando si ferma', (tester) async {
    final repo = DemoChatRepository();
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    final typing = repo.typingOf('c-main');

    // I puntini girano sempre: niente pumpAndSettle mentre si vedono.
    typing.simulate('p2', TypingKind.testo);
    await tester.pump();
    await tester.pump();
    expect(find.text('Marco sta scrivendo'), findsOneWidget);
    typing.simulate('p3', TypingKind.vocale);
    await tester.pump();
    await tester.pump();
    expect(find.text('Marco e Luca stanno scrivendo'), findsOneWidget);
    typing
      ..simulate('p2', null)
      ..simulate('p3', null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Tutto il club'), findsOneWidget);
    await tester.pumpAndSettle();

    final before = typing.pings;
    await tester.enterText(find.byType(TextField), 'Arrivo');
    await tester.pump();
    expect(typing.pings, greaterThan(before));
    expect(typing.lastKind, TypingKind.testo);
    final stops = typing.stops;
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(typing.stops, greaterThan(stops));
  });

  testWidgets('Menzioni: "@" e le prime lettere propongono i compagni; scelto, '
      'il nome resta nel testo e va nel messaggio', (tester) async {
    final repo = DemoChatRepository();
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    await tester.enterText(find.byType(TextField), 'Stasera @mar');
    await tester.pump();
    final suggestions = find.byType(MentionSuggestions);
    expect(
      find.descendant(of: suggestions, matching: find.text('Marco Rossi')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: suggestions, matching: find.text('Marco Rossi')),
    );
    await tester.pump();
    expect(suggestions, findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Stasera @Marco Rossi ');

    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    final sent = (await repo.searchMessages('Stasera @Marco')).single;
    expect(sent.meta['mentions'], ['p2']);
  });
}
