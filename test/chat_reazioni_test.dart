import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/auth/notify_prefs.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/features/chat/chat_alerts.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/chat/emoji_picker.dart';
import 'package:milanac/shared/link_text.dart';

import 'chat_test.dart' show openChannel, startChat;
import 'home_test.dart' show todayAt;

/// Il server non salva le reazioni.
class _NoReactions extends DemoChatRepository {
  @override
  Future<ChatMessage> react(ChatMessage m, String? emoji) async =>
      throw Exception('errore del server');
}

/// La chat di esempio senza le reazioni già messe sul messaggio di Marco: i test
/// partono da un messaggio pulito.
T clean<T extends DemoChatRepository>(T repo) {
  for (final who in ['p3', 'p4', 'p6']) {
    repo.reactElsewhere('m1', who, null);
  }
  return repo;
}

/// L'etichetta di una reazione sotto una bolla: emoji e quante persone.
Finder reaction(String emoji, int count) => find.bySemanticsLabel(
  '$emoji, ${count == 1 ? '1 reazione' : '$count reazioni'}',
);

const lobby = 'Stasera tutti in lobby alle 21:15!';

/// La bolla del messaggio di Marco (lo stesso testo compare anche in una citazione).
final bubble = find.widgetWithText(LinkText, lobby);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  group('modello', () {
    ChatMessage message(Map<String, dynamic> meta) => ChatMessage(
      id: 'x',
      channelId: 'c',
      createdAt: DateTime(2026, 11, 17),
      body: 'Ciao',
      meta: meta,
    );

    test('le reazioni si leggono dal meta senza fidarsi', () {
      expect(message(const {}).reactions, isEmpty);
      expect(message(const {'reactions': 'no'}).reactions, isEmpty);
      expect(
        message(const {
          'reactions': {'a': '👍', 'b': 3, 'c': '', 'd': '🔥'},
        }).reactions,
        {'a': '👍', 'd': '🔥'},
      );
    });

    test('una reazione a testa: si mette, si cambia, si toglie', () {
      final m = message(const {'type': 'announcement'});
      final one = m.withReaction('a', '👍');
      expect(one.reactions, {'a': '👍'});
      final two = one.withReaction('b', '🔥').withReaction('a', '❤️');
      expect(two.reactions, {'a': '❤️', 'b': '🔥'});
      final none = two.withReaction('a', null).withReaction('b', '');
      expect(none.reactions, isEmpty);
      // Senza reazioni la chiave sparisce; il resto del meta resta.
      expect(none.meta, {'type': 'announcement'});
      expect(two.isAnnouncement, isTrue);
    });
  });

  group('emoji', () {
    test('il selettore ha solo emoji singole, valide come reazioni', () {
      for (final category in emojiCategories) {
        expect(
          category.emojis.toSet(),
          hasLength(category.emojis.length),
          reason: 'doppioni in ${category.label}',
        );
        for (final emoji in category.emojis) {
          expect(emoji.characters, hasLength(1), reason: emoji);
          expect(isReactionEmoji(emoji), isTrue, reason: emoji);
        }
      }
      for (final emoji in quickReactions) {
        expect(isReactionEmoji(emoji), isTrue, reason: emoji);
      }
    });

    test('una reazione è un\'emoji, non un testo', () {
      for (final ok in ['👍', '❤️', '⚽', '🇮🇹', '👍🏽', '👨‍👩‍👧‍👦']) {
        expect(isReactionEmoji(ok), isTrue, reason: ok);
      }
      for (final no in ['', 'ok', '👍 ok', '12', '<b>', '🏽', '👍' * 13]) {
        expect(isReactionEmoji(no), isFalse, reason: no);
      }
    });

    test('messaggi di sole emoji (fino a tre) si riconoscono', () {
      expect(emojiOnlyCount('🔥'), 1);
      expect(emojiOnlyCount(' 🔥🔥 '), 2);
      expect(emojiOnlyCount('👍🏽 ⚽ ❤️'), 3);
      expect(emojiOnlyCount('🇮🇹'), 1);
      expect(emojiOnlyCount('🔥🔥🔥🔥'), 0);
      expect(emojiOnlyCount('ok 🔥'), 0);
      expect(emojiOnlyCount('12'), 0);
      expect(emojiOnlyCount(''), 0);
    });
  });

  group('reazioni in conversazione', () {
    testWidgets('dal menu del messaggio: si mette, si vede, si toglie', (
      tester,
    ) async {
      final repo = clean(DemoChatRepository());
      await startChat(tester, repo: repo);
      await openChannel(tester, 'Generale');

      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      // Le reazioni rapide stanno sopra le azioni di sempre.
      expect(find.bySemanticsLabel('Reagisci con 👍'), findsOneWidget);
      expect(find.text('Rispondi'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Reagisci con 👍'));
      await tester.pumpAndSettle();
      expect(reaction('👍', 1), findsOneWidget);

      // Un altro reagisce con la stessa, un terzo con un'altra: la più messa è prima.
      repo.reactElsewhere('m1', 'p3', '👍');
      repo.reactElsewhere('m1', 'p4', '🔥');
      await tester.pumpAndSettle();
      expect(reaction('👍', 2), findsOneWidget);
      expect(reaction('🔥', 1), findsOneWidget);
      expect(
        tester.getTopLeft(reaction('👍', 2)).dx,
        lessThan(tester.getTopLeft(reaction('🔥', 1)).dx),
      );

      // Toccare la reazione di un altro la fa propria (una a testa: la prima va via).
      await tester.tap(reaction('🔥', 1));
      await tester.pumpAndSettle();
      expect(reaction('🔥', 2), findsOneWidget);
      expect(reaction('👍', 1), findsOneWidget);

      // Toccare la propria la toglie.
      await tester.tap(reaction('🔥', 2));
      await tester.pumpAndSettle();
      expect(reaction('🔥', 1), findsOneWidget);

      // Nel menu la propria reazione è evidenziata: ritoccarla la toglie.
      await tester.tap(reaction('👍', 1));
      await tester.pumpAndSettle();
      expect(reaction('👍', 2), findsOneWidget);
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Reagisci con 👍'));
      await tester.pumpAndSettle();
      expect(reaction('👍', 1), findsOneWidget);
    });

    testWidgets('"+" apre tutte le emoji; tenendo premuto si vede chi ha '
        'reagito', (tester) async {
      final repo = clean(DemoChatRepository());
      await startChat(tester, repo: repo);
      await openChannel(tester, 'Generale');
      repo.reactElsewhere('m1', 'p3', '👏');
      await tester.pumpAndSettle();

      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Altre emoji'));
      await tester.pumpAndSettle();
      expect(find.text('Reagisci'), findsOneWidget);
      await tester.tap(find.byTooltip('Animali e natura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🐐'));
      await tester.pumpAndSettle();
      expect(reaction('🐐', 1), findsOneWidget);

      await tester.longPress(reaction('👏', 1));
      await tester.pumpAndSettle();
      expect(find.text('2 reazioni'), findsOneWidget);
      // Prima la propria, che da qui si toglie; poi gli altri per nome.
      expect(find.text('Tu'), findsOneWidget);
      expect(find.text('Luca Bianchi'), findsWidgets);
      await tester.tap(find.text('Tocca per toglierla'));
      await tester.pumpAndSettle();
      expect(reaction('🐐', 1), findsNothing);
      expect(reaction('👏', 1), findsOneWidget);
    });

    testWidgets('se il server non la salva la reazione torna com\'era, e lo '
        'si dice', (tester) async {
      await startChat(tester, repo: clean(_NoReactions()));
      await openChannel(tester, 'Generale');
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Reagisci con 🔥'));
      await tester.pumpAndSettle();
      expect(reaction('🔥', 1), findsNothing);
      expect(find.textContaining('Reazione non salvata'), findsOneWidget);
    });

    testWidgets('con il mouse il menu si apre con il tasto destro', (
      tester,
    ) async {
      await startChat(tester, repo: clean(DemoChatRepository()));
      await openChannel(tester, 'Generale');
      await tester.tap(bubble, buttons: 2);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Reagisci con ⚽'), findsOneWidget);
    });
  });

  testWidgets('nella demo il messaggio di esempio ha già le sue reazioni', (
    tester,
  ) async {
    await startChat(tester, repo: DemoChatRepository());
    await openChannel(tester, 'Generale');
    expect(reaction('👍', 2), findsOneWidget);
    expect(reaction('🔥', 1), findsOneWidget);
  });

  group('emoji nel messaggio', () {
    testWidgets('il selettore scrive dove sta il cursore; "indietro" lo '
        'chiude; le sole emoji si vedono grandi', (tester) async {
      await startChat(tester, repo: DemoChatRepository());
      await openChannel(tester, 'Generale');
      final field = find.byType(TextField);

      await tester.enterText(field, 'Forza ragazzi');
      await tester.tap(find.byTooltip('Emoji'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPanel), findsOneWidget);
      // Il cursore è in fondo al testo scritto: l'emoji va lì.
      await tester.tap(find.byTooltip('Calcio e sport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('⚽'));
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Forza ragazzi⚽',
      );

      // "Indietro" chiude il selettore, non la conversazione.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPanel), findsNothing);
      expect(field, findsOneWidget);
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();
      expect(find.text('Forza ragazzi⚽'), findsOneWidget);

      // L'emoji appena usata è tra le recenti, che si aprono per prime.
      await tester.tap(find.byTooltip('Emoji'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Usate di recente'), findsOneWidget);
      final ball = find.descendant(
        of: find.byType(EmojiPanel),
        matching: find.text('⚽'),
      );
      await tester.tap(ball);
      await tester.tap(ball);
      await tester.pump();
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();
      final big = tester.widget<LinkText>(find.widgetWithText(LinkText, '⚽⚽'));
      expect(big.style!.fontSize, 38);
      final normal = tester.widget<LinkText>(
        find.widgetWithText(LinkText, 'Forza ragazzi⚽'),
      );
      expect(normal.style!.fontSize, 16);
    });
  });

  group('avvisi dei messaggi nuovi con l\'app aperta', () {
    var n = 0;
    ChatMessage incoming(
      String body, {
      String author = 'p2',
      String channel = 'c-main',
      Map<String, dynamic> meta = const {},
    }) => ChatMessage(
      // Id sempre nuovi: lo stesso messaggio non avvisa due volte.
      id: 'avviso-${n++}-${DateTime.now().microsecondsSinceEpoch}',
      channelId: channel,
      authorId: author,
      body: body,
      meta: meta,
      createdAt: todayAt(20),
    );

    tearDown(() => messengerKey.currentState?.clearSnackBars());

    test('titolo e testo come nelle notifiche push', () {
      ChatMessage m(String? body, [Map<String, dynamic> meta = const {}]) =>
          ChatMessage(
            id: 'x',
            channelId: 'c',
            createdAt: DateTime(2026),
            body: body,
            meta: meta,
          );
      String text(ChatMessage x) {
        final a = chatAlertText(x, channelName: 'Generale', authorName: 'Luca');
        return '${a.title} | ${a.body}';
      }

      expect(text(m('Ciao')), '#Generale · Luca | Ciao');
      expect(
        text(m('Domani alle 22', const {'type': 'announcement'})),
        '📣 Avviso del Direttivo · Luca | Domani alle 22',
      );
      expect(
        text(
          m('Quando?', const {
            'type': 'poll',
            'options': ['A', 'B'],
          }),
        ),
        '#Generale · Luca | 📊 Sondaggio: Quando?',
      );
      final long = chatAlertText(
        m('x' * 300),
        channelName: 'Generale',
        authorName: 'Luca',
      ).body;
      expect(long, hasLength(138));
      expect(long, endsWith('…'));
    });

    testWidgets('un messaggio in un altro canale avvisa, con "Apri"', (
      tester,
    ) async {
      final repo = DemoChatRepository();
      await startChat(tester, repo: repo);
      repo.receive(incoming('Chi c\'è stasera?'));
      await tester.pumpAndSettle();
      expect(
        find.text('#Generale · Marco Rossi\nChi c\'è stasera?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Apri'));
      await tester.pumpAndSettle();
      // La conversazione si apre sul messaggio arrivato.
      expect(find.byTooltip('Emoji'), findsOneWidget);
      expect(find.text('Chi c\'è stasera?'), findsOneWidget);

      // Nel canale che si sta leggendo i messaggi nuovi non avvisano.
      messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();
      repo.receive(incoming('Io ci sono'));
      await tester.pumpAndSettle();
      expect(find.text('#Generale · Marco Rossi\nIo ci sono'), findsNothing);
      expect(find.text('Io ci sono'), findsOneWidget);
    });

    testWidgets('niente avviso per i propri messaggi, i canali silenziati e '
        'la chat spenta nelle notifiche (salvo gli avvisi ufficiali)', (
      tester,
    ) async {
      final repo = DemoChatRepository();
      await repo.setMuted('c-main', true);
      final container = await startChat(tester, repo: repo);

      repo.receive(incoming('Silenziato'));
      repo.receive(incoming('Mio', author: 'demo', channel: 'c-tattiche'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      // Chat spenta nelle notifiche: un messaggio normale non avvisa, l'avviso
      // ufficiale del Direttivo sì.
      final me = container.read(profileProvider).value!;
      await container
          .read(notifyPrefsRepositoryProvider)
          .save(me.notifyPrefs.set(NotifyCategory.chat, false));
      await tester.pumpAndSettle();
      repo.receive(incoming('Normale', channel: 'c-tattiche'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      repo.receive(
        incoming(
          'Domani amichevole',
          channel: 'c-tattiche',
          meta: const {'type': 'announcement'},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('📣 Avviso del Direttivo · Marco Rossi'),
        findsOneWidget,
      );
    });

    testWidgets('lo stesso messaggio arrivato anche come notifica push avvisa '
        'una volta sola', (tester) async {
      final repo = DemoChatRepository();
      await startChat(tester, repo: repo);
      final m = incoming('Una volta sola');
      repo.receive(m);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();
      // La push dello stesso messaggio (con il suo id) non ripete l'avviso.
      PushService.instance.showInApp(
        title: '#Generale · Marco Rossi',
        body: 'Una volta sola',
        data: {'route': '/chat/main', 'channel': 'main', 'message': m.id},
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
