import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/errors.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/chat/poll.dart';
import 'package:milanac/features/chat/poll_widgets.dart';

import 'chat_test.dart' show history, openChannel, startChat;
import 'home_test.dart' show todayAt;

const _question = "Quando giochiamo l'amichevole con i Lupi?";

/// La percentuale scritta accanto a una risposta del sondaggio [messageId].
Finder _percentOf(String messageId, int option) => find.descendant(
  of: find.byKey(ValueKey('sondaggio-$messageId-$option')),
  matching: find.textContaining('%'),
);

String _percentText(WidgetTester tester, String messageId, int option) =>
    tester.widget<Text>(_percentOf(messageId, option)).data!;

/// La chat demo, con il sondaggio dei Lupi e i voti chiesti al server che falliscono
/// se [failVotes].
class _Chat extends DemoChatRepository {
  _Chat({this.failVotes = false, super.messages})
    : super(clock: () => todayAt(20));
  final bool failVotes;

  /// Se c'è, il voto parte solo quando il test la completa (rete lenta).
  Completer<void>? slowVote;

  /// Se c'è, i voti arrivano da qui (il primo caricamento si fa aspettare).
  StreamController<List<PollVote>>? slowVotes;

  /// Voti chiesti al server.
  final sent = <Set<int>>[];

  @override
  Future<void> votePoll(String messageId, Set<int> options) async {
    sent.add(options);
    await slowVote?.future;
    if (failVotes) throw const AppError(pollsMissing);
    return super.votePoll(messageId, options);
  }

  @override
  Stream<List<PollVote>> watchPollVotes(String messageId) =>
      slowVotes?.stream ?? super.watchPollVotes(messageId);
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  tearDown(() => PushService.instance.shouldShowInApp = null);

  ChatMessage pollMessage(Map<String, dynamic> meta, {String body = 'Chi?'}) =>
      ChatMessage(
        id: 'x',
        channelId: 'c',
        body: body,
        meta: meta,
        createdAt: DateTime(2026, 10, 30),
      );

  test('Sondaggio letto dal messaggio: opzioni, scelta multipla, chiusura; '
      'un meta che non torna non è un sondaggio', () {
    final poll = ChatPoll.of(
      pollMessage({
        'type': 'poll',
        'options': [' Martedì ', 'Mercoledì'],
        'multiple': true,
        'closed_at': '2026-10-30T21:00:00Z',
      }),
    )!;
    expect(poll.question, 'Chi?');
    expect(poll.options, ['Martedì', 'Mercoledì']);
    expect(poll.multiple, isTrue);
    expect(poll.closed, isTrue);
    expect(
      ChatPoll.of(pollMessage(ChatPoll.meta(['A', 'B'])))!.closed,
      isFalse,
    );
    for (final meta in <Map<String, dynamic>>[
      {'type': 'poll', 'options': 'A,B'},
      {
        'type': 'poll',
        'options': ['Solo una'],
      },
      {
        'type': 'poll',
        'options': ['A', 2],
      },
      {
        'type': 'poll',
        'options': ['A', '  '],
      },
      {
        'type': 'poll',
        'options': [for (var i = 0; i < 11; i++) '$i'],
      },
      {
        'type': 'announcement',
        'options': ['A', 'B'],
      },
    ]) {
      expect(ChatPoll.of(pollMessage(meta)), isNull, reason: '$meta');
    }
    expect(
      ChatPoll.of(pollMessage(ChatPoll.meta(['A', 'B']), body: '  ')),
      isNull,
    );

    expect(ChatPoll.problemWith(' ', ['A', 'B']), 'Scrivi la domanda.');
    expect(
      ChatPoll.problemWith('Chi?', ['A', ' ', '']),
      'Servono almeno due risposte.',
    );
    expect(
      ChatPoll.problemWith('Chi?', ['Sì', ' sì ']),
      'Due risposte sono uguali.',
    );
    expect(ChatPoll.problemWith('Chi?', ['Sì', 'No', '']), isNull);
  });

  test('Risultati: percentuali su chi ha votato, i più votati, il mio voto; '
      'i voti ritirati e le opzioni fuori elenco non contano', () {
    const poll = ChatPoll(
      question: 'Che cosa portiamo?',
      options: ['Maglie', 'Cuffie', 'Pizza'],
      multiple: true,
    );
    PollVote vote(String who, Set<int> options) =>
        PollVote(messageId: 'x', userId: who, options: options);
    final tally = PollTally(poll, [
      vote('a', {0, 2}),
      vote('b', {2}),
      vote('me', {0, 7}),
      vote('c', {}),
    ], me: 'me');
    expect(tally.total, 3);
    expect(tally.totalLabel, '3 voti');
    expect(tally.count(0), 2);
    expect(tally.count(1), 0);
    expect(tally.share(2), closeTo(2 / 3, 1e-9));
    expect(tally.leaders, {0, 2});
    expect(tally.mine, {0});
    expect(tally.voters[2], ['a', 'b']);

    final empty = PollTally(poll, const [], me: 'me');
    expect(empty.totalLabel, 'Nessun voto');
    expect(empty.leaders, isEmpty);
    expect(empty.share(0), 0);
    expect(
      PollTally(poll, [
        vote('a', {1}),
      ]).totalLabel,
      '1 voto',
    );

    final message = pollMessage(ChatPoll.meta(['A', 'B']));
    expect(message.isPoll, isTrue);
    expect(message.summary, '📊 Chi?');
    expect(
      const ChannelOverview(
        lastBody: 'Chi viene?',
        lastAuthor: 'Marco Rossi',
        lastType: 'poll',
      ).preview,
      'Marco Rossi: 📊 Chi viene?',
    );
  });

  testWidgets('Votare: i risultati compaiono dopo il voto, si cambia idea, si '
      'ritira; i voti degli altri arrivano in tempo reale; chi ha votato', (
    tester,
  ) async {
    final repo = _Chat();
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Milan AC');

    expect(find.text('SONDAGGIO'), findsOneWidget);
    expect(find.text(_question), findsOneWidget);
    // Prima di votare niente percentuali: solo quanti hanno votato.
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('3 voti'), findsOneWidget);
    expect(find.text('Ritira il voto'), findsNothing);

    await tester.tap(find.text('Giovedì'));
    await tester.pumpAndSettle();
    expect(find.text('4 voti'), findsOneWidget);
    expect(_percentText(tester, 'm8', 0), '25%');
    expect(_percentText(tester, 'm8', 1), '50%');
    expect(_percentText(tester, 'm8', 2), '25%');
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Giovedì, 25 per cento, 1 voto'),
      ),
      matchesSemantics(
        label: 'Giovedì, 25 per cento, 1 voto',
        isButton: true,
        hasTapAction: true,
        isSelected: true,
        hasSelectedState: true,
      ),
    );

    // Si cambia idea: una sola risposta, il voto passa a mercoledì.
    await tester.tap(find.text('Mercoledì'));
    await tester.pumpAndSettle();
    expect(find.text('4 voti'), findsOneWidget);
    expect(_percentText(tester, 'm8', 1), '75%');
    expect(_percentText(tester, 'm8', 2), '0%');

    // Un altro vota mentre si guarda.
    repo.voteElsewhere('m8', 'p5', {2});
    await tester.pumpAndSettle();
    expect(find.text('5 voti'), findsOneWidget);
    expect(_percentText(tester, 'm8', 1), '60%');

    // Chi ha votato, risposta per risposta.
    await tester.tap(find.text('5 voti'));
    await tester.pumpAndSettle();
    expect(find.text('CHI HA VOTATO'), findsOneWidget);
    expect(find.text('MERCOLEDÌ · 3'), findsOneWidget);
    expect(find.text('MARTEDÌ · 1'), findsOneWidget);
    expect(find.text('GIOVEDÌ · 1'), findsOneWidget);
    Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );
    expect(inSheet('Tu'), findsOneWidget);
    expect(inSheet('Marco Rossi'), findsOneWidget);
    expect(inSheet('Andrea Neri'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ritira il voto'));
    await tester.pumpAndSettle();
    expect(find.text('4 voti'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('Nuovo sondaggio: domanda e risposte controllate, più risposte, '
      'voto doppio, anteprima nella lista e chiusura', (tester) async {
    final container = await startChat(tester);
    await openChannel(tester, 'Generale');

    await tester.tap(find.byTooltip('Crea un sondaggio'));
    await tester.pumpAndSettle();
    expect(find.text('NUOVO SONDAGGIO'), findsOneWidget);
    await tester.tap(find.text('Crea il sondaggio'));
    await tester.pumpAndSettle();
    expect(find.text('Scrivi la domanda.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('sondaggio-domanda')),
      'Che cosa portiamo al torneo?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sondaggio-risposta-0')),
      'Maglie nuove',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sondaggio-risposta-1')),
      ' maglie NUOVE ',
    );
    await tester.tap(find.text('Crea il sondaggio'));
    await tester.pumpAndSettle();
    expect(find.text('Due risposte sono uguali.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('sondaggio-risposta-1')),
      'Cuffie',
    );
    await tester.tap(find.text('Aggiungi una risposta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sondaggio-risposta-2')),
      'Pizza',
    );
    // Una quarta risposta, poi tolta.
    await tester.tap(find.text('Aggiungi una risposta'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Togli la risposta 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Togli la risposta 4'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sondaggio-risposta-3')), findsNothing);
    await tester.tap(find.text('Più risposte'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crea il sondaggio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crea il sondaggio'));
    await tester.pumpAndSettle();

    expect(find.text('NUOVO SONDAGGIO'), findsNothing);
    expect(find.text('SONDAGGIO · PIÙ RISPOSTE'), findsOneWidget);
    expect(find.text('Che cosa portiamo al torneo?'), findsOneWidget);
    final sent = history(container, 'c-main').messages.first;
    expect(sent.isPoll, isTrue);
    expect(sent.isLocal, isFalse);
    expect(sent.meta['options'], ['Maglie nuove', 'Cuffie', 'Pizza']);
    expect(sent.meta['multiple'], isTrue);

    // Con più risposte ogni tocco aggiunge (o toglie) una scelta.
    await tester.tap(find.text('Maglie nuove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pizza'));
    await tester.pumpAndSettle();
    expect(find.text('1 voto'), findsOneWidget);
    expect(_percentText(tester, sent.id, 0), '100%');
    expect(_percentText(tester, sent.id, 1), '0%');
    expect(_percentText(tester, sent.id, 2), '100%');
    await tester.tap(find.text('Maglie nuove'));
    await tester.pumpAndSettle();
    expect(_percentText(tester, sent.id, 0), '0%');

    // Chi l'ha creato lo chiude: niente più voti, la più votata in evidenza.
    await tester.longPress(find.text('Che cosa portiamo al torneo?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiudi il sondaggio'));
    await tester.pumpAndSettle();
    expect(find.text('Chiudere il sondaggio?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('SONDAGGIO CHIUSO · PIÙ RISPOSTE'), findsOneWidget);
    expect(find.text('Ritira il voto'), findsNothing);
    await tester.tap(find.text('Cuffie'));
    await tester.pumpAndSettle();
    expect(_percentText(tester, sent.id, 1), '0%');
    await tester.longPress(find.text('Che cosa portiamo al torneo?'));
    await tester.pumpAndSettle();
    expect(find.text('Chiudi il sondaggio'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Nell'elenco dei canali l'ultimo messaggio è il sondaggio.
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(
      find.text('Demo Direttivo: 📊 Che cosa portiamo al torneo?'),
      findsOneWidget,
    );
  });

  /// Il sondaggio dei Lupi scritto da Marco Rossi (non da chi guarda), già votato da due.
  _Chat othersPoll({bool failVotes = false}) {
    final repo = _Chat(
      failVotes: failVotes,
      messages: [
        ChatMessage(
          id: 'q1',
          channelId: 'c-milanac',
          authorId: 'p2',
          body: _question,
          meta: ChatPoll.meta(['Martedì', 'Mercoledì']),
          createdAt: todayAt(19),
        ),
      ],
    );
    repo
      ..voteElsewhere('q1', 'p2', {1})
      ..voteElsewhere('q1', 'p3', {0});
    return repo;
  }

  testWidgets('Un giocatore non chiude il sondaggio di un altro; voto non '
      'salvato (server senza sondaggi): lo si dice e non cambia nulla', (
    tester,
  ) async {
    await startChat(
      tester,
      repo: othersPoll(failVotes: true),
      overrides: [
        profileProvider.overrideWith(
          (ref) => Stream<Profile?>.value(
            const Profile(
              id: 'demo',
              displayName: 'Demo Giocatore',
              role: ClubRole.giocatore,
              registrationCompleted: true,
            ),
          ),
        ),
      ],
    );
    await openChannel(tester, 'Milan AC');
    await tester.longPress(find.text(_question));
    await tester.pumpAndSettle();
    expect(find.text('Copia testo'), findsOneWidget);
    expect(find.text('Chiudi il sondaggio'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Martedì'));
    await tester.pumpAndSettle();
    expect(find.textContaining(pollsMissing), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('2 voti'), findsOneWidget);
    expect(find.byType(PollCard), findsOneWidget);
  });

  testWidgets('Il Direttivo chiude anche il sondaggio di un altro', (
    tester,
  ) async {
    await startChat(tester, repo: othersPoll());
    await openChannel(tester, 'Milan AC');
    await tester.longPress(find.text(_question));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chiudi il sondaggio'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Chiudi'));
    await tester.pumpAndSettle();
    // Chiuso, i risultati si vedono anche senza aver votato.
    expect(find.text('SONDAGGIO CHIUSO'), findsOneWidget);
    expect(_percentText(tester, 'q1', 0), '50%');
    expect(_percentText(tester, 'q1', 1), '50%');
  });

  test('Lunghezze come le conta il database: le emoji composte valgono più '
      'caratteri', () {
    // 👨‍👩‍👧 sono 5 punti di codice, 👍🏽 sono 2.
    expect(
      ChatPoll.problemWith('${'a' * 299}👨‍👩‍👧', ['Sì', 'No']),
      contains('La domanda è troppo lunga'),
    );
    expect(ChatPoll.problemWith('a' * 300, ['Sì', 'No']), isNull);
    expect(
      ChatPoll.problemWith('Chi?', ['${'b' * 79}👍🏽', 'No']),
      contains('Una risposta è troppo lunga'),
    );
    expect(ChatPoll.problemWith('Chi?', ['b' * 80, 'No']), isNull);
  });

  testWidgets('Il proprio voto cambiato da un altro telefono si vede anche '
      'subito dopo aver votato da qui', (tester) async {
    final repo = _Chat();
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Milan AC');
    // Nella demo il tempo reale riporta il voto prima della risposta del server.
    await tester.tap(find.text('Giovedì'));
    await tester.pumpAndSettle();
    expect(_percentText(tester, 'm8', 2), '25%');
    repo.voteElsewhere('m8', 'demo', {0});
    await tester.pumpAndSettle();
    expect(_percentText(tester, 'm8', 0), '50%');
    expect(_percentText(tester, 'm8', 2), '0%');
  });

  testWidgets(
    'Finché il proprio voto non è arrivato le risposte non si toccano '
    '(con più risposte il voto di prima si perderebbe)',
    (tester) async {
      final repo = _Chat(
        messages: [
          ChatMessage(
            id: 'q1',
            channelId: 'c-milanac',
            authorId: 'p2',
            body: 'Che cosa portiamo?',
            meta: ChatPoll.meta(['Maglie', 'Cuffie', 'Pizza'], multiple: true),
            createdAt: todayAt(19),
          ),
        ],
      )..slowVotes = StreamController<List<PollVote>>.broadcast();
      addTearDown(repo.slowVotes!.close);
      await startChat(tester, repo: repo);
      await openChannel(tester, 'Milan AC');
      await tester.tap(find.text('Cuffie'));
      await tester.pumpAndSettle();
      expect(repo.sent, isEmpty);

      // Arriva il voto di prima (Maglie e Pizza): il tocco aggiunge Cuffie.
      repo.slowVotes!.add(const [
        PollVote(messageId: 'q1', userId: 'demo', options: {0, 2}),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuffie'));
      await tester.pumpAndSettle();
      expect(repo.sent, [
        {0, 1, 2},
      ]);
    },
  );

  testWidgets('Il voto in corso resta al suo sondaggio anche se arriva un '
      'messaggio e la conversazione scorre', (tester) async {
    PollVote vote(String poll, String who, Set<int> o) =>
        PollVote(messageId: poll, userId: who, options: o);
    final repo = _Chat(
      messages: [
        for (final (id, q, at) in [
          ('q1', 'Prima domanda?', 18),
          ('q2', 'Seconda domanda?', 19),
        ])
          ChatMessage(
            id: id,
            channelId: 'c-milanac',
            authorId: 'p2',
            body: q,
            meta: ChatPoll.meta(['Sì', 'No']),
            createdAt: todayAt(at),
          ),
      ],
    )..slowVote = Completer<void>();
    repo.voteElsewhere('q1', 'p3', vote('q1', 'p3', {1}).options);
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Milan AC');

    // Si vota la prima; mentre parte arriva un messaggio e tutto scorre di un posto.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('sondaggio-q1-0')),
        matching: find.text('Sì'),
      ),
    );
    await tester.pump();
    repo.receive(
      ChatMessage(
        id: 'n1',
        channelId: 'c-milanac',
        authorId: 'p3',
        body: 'Ci sono',
        createdAt: todayAt(19, 30),
      ),
    );
    await tester.pumpAndSettle();
    repo.slowVote!.complete();
    await tester.pumpAndSettle();
    expect(_percentOf('q1', 0), findsOneWidget);
    expect(_percentText(tester, 'q1', 0), '50%');
    // La seconda non risulta votata.
    expect(_percentOf('q2', 0), findsNothing);
  });

  testWidgets('Sondaggio chiuso da un altro fuori dagli ultimi messaggi del '
      'canale: la bolla lo mostra chiuso lo stesso', (tester) async {
    final repo = _Chat();
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Milan AC');
    expect(find.text('SONDAGGIO'), findsOneWidget);
    repo.closePollElsewhere('m8', inChannel: false);
    await tester.pumpAndSettle();
    expect(find.text('SONDAGGIO CHIUSO'), findsOneWidget);
    // Chiuso: i risultati si vedono e il menu non offre più la chiusura.
    expect(_percentText(tester, 'm8', 1), '67%');
    await tester.longPress(find.text(_question));
    await tester.pumpAndSettle();
    expect(find.text('Chiudi il sondaggio'), findsNothing);
  });
}
