import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/features/chat/channel_messages.dart';
import 'package:milanac/features/chat/chat_outbox.dart';
import 'package:milanac/features/chat/chat_repository.dart';

/// Chat demo che, senza rete ([offline]), fallisce come il telefono senza
/// connessione; [sent] dice che cosa è arrivato al server, nell'ordine.
class _OfflineRepository extends DemoChatRepository {
  bool offline = false;
  final sent = <String>[];

  @override
  Future<ChatMessage> send(
    String channelId, {
    String? id,
    String? body,
    Uint8List? image,
    Uint8List? audio,
    int? durationS,
    Uint8List? replay,
    String? replyTo,
    Map<String, dynamic>? meta,
  }) async {
    if (offline) {
      throw const SocketException('Failed host lookup: supabase.co');
    }
    final saved = await super.send(
      channelId,
      id: id,
      body: body,
      image: image,
      audio: audio,
      durationS: durationS,
      replay: replay,
      replyTo: replyTo,
      meta: meta,
    );
    sent.add(body ?? '');
    return saved;
  }
}

ProviderContainer _container(ChatRepository repo, ChatOutbox outbox) {
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repo),
      chatOutboxProvider.overrideWithValue(outbox),
      currentUserIdProvider.overrideWith((ref) => 'demo'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

List<ChatMessage> _mine(ProviderContainer c) => [
  for (final m in c.read(messagesProvider('c-main')).value?.messages ?? [])
    if (m.authorId == 'demo') m,
];

void main() {
  test(
    'In uscita sul telefono: testo, foto e vocale tornano uguali, divisi per '
    'account e canale; un file rovinato si salta',
    () async {
      final dir = await Directory.systemTemp.createTemp('chat_uscita');
      addTearDown(() => dir.delete(recursive: true));
      final outbox = FileChatOutbox(root: () async => dir);
      final at = DateTime(2026, 10, 24, 21, 30);
      final m = ChatMessage(
        id: newMessageId(),
        channelId: 'c-main',
        authorId: 'demo',
        body: 'Ci sono, arrivo in ritardo',
        durationS: 12,
        replyTo: 'm1',
        meta: const {
          'mentions': ['p2'],
        },
        createdAt: at,
        localImage: Uint8List.fromList([1, 2, 3]),
        localAudio: Uint8List.fromList([4, 5]),
      );
      await outbox.put('demo', m);
      await outbox.put(
        'demo',
        ChatMessage(
          id: newMessageId(),
          channelId: 'c-tattiche',
          body: 'Schema nuovo',
          createdAt: at.add(const Duration(minutes: 1)),
        ),
      );
      await outbox.put(
        'p2',
        ChatMessage(
          id: newMessageId(),
          channelId: 'c-main',
          body: 'Di un altro',
          createdAt: at,
        ),
      );

      final back = (await outbox.pending('demo', channelId: 'c-main')).single;
      expect(back.id, m.id);
      expect(back.body, 'Ci sono, arrivo in ritardo');
      expect(back.durationS, 12);
      expect(back.replyTo, 'm1');
      expect(back.meta['mentions'], ['p2']);
      expect(back.createdAt, at);
      expect(back.localImage, [1, 2, 3]);
      expect(back.localAudio, [4, 5]);
      expect(back.localReplay, isNull);
      expect(await outbox.pending('demo'), hasLength(2));
      expect(await outbox.pending('p2'), hasLength(1));

      // L'app chiusa a metà scrittura lascia un file rovinato: non blocca gli altri.
      File(
        [
          dir.path,
          'chat_in_uscita',
          'demo',
          'rotto.json',
        ].join(Platform.pathSeparator),
      ).writeAsStringSync('{non è json');
      expect(await outbox.pending('demo'), hasLength(2));

      // Partito: via il messaggio e i suoi allegati.
      await outbox.remove('demo', m.id);
      expect(await outbox.pending('demo', channelId: 'c-main'), isEmpty);
      final left = Directory(
        [dir.path, 'chat_in_uscita', 'demo'].join(Platform.pathSeparator),
      ).listSync().map((f) => f.path);
      expect(left.where((p) => p.contains(m.id)), isEmpty);
    },
  );

  testWidgets(
    'Senza rete il messaggio aspetta (niente errore), riparte da solo '
    'appena torna, nell\'ordine in cui è stato scritto e senza doppioni',
    (tester) async {
      final repo = _OfflineRepository();
      final outbox = MemoryChatOutbox();
      final c = _container(repo, outbox);
      final sub = c.listen(messagesProvider('c-main'), (_, _) {});
      addTearDown(sub.close);
      await c.read(messagesProvider('c-main').future);
      final chat = c.read(messagesProvider('c-main').notifier);

      repo.offline = true;
      final first = await chat.send(body: 'Ci sono');
      expect(first.waiting, isTrue);
      expect(first.error, isNull);
      final second = await chat.send(body: 'Arrivo alle 21:40');
      expect(second.waiting, isTrue);
      await tester.pump();
      expect(_mine(c).where((m) => m.waiting), hasLength(2));
      expect(_mine(c).where((m) => m.failed), isEmpty);
      expect(await outbox.pending('demo'), hasLength(2));

      // Al primo tentativo da solo (2 secondi) la rete manca ancora: si riprova più
      // tardi (5 secondi), sempre nell'ordine.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(repo.sent, isEmpty);
      expect(_mine(c).where((m) => m.waiting), hasLength(2));

      repo.offline = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(repo.sent, ['Ci sono', 'Arrivo alle 21:40']);
      expect(_mine(c).where((m) => m.isLocal), isEmpty);
      expect(await outbox.pending('demo'), isEmpty);

      // Niente altri tentativi: il timer si è fermato.
      await tester.pump(const Duration(minutes: 1));
      expect(repo.sent, hasLength(2));
    },
  );

  testWidgets('Toccato mentre aspetta la rete: parte subito', (tester) async {
    final repo = _OfflineRepository()..offline = true;
    final c = _container(repo, MemoryChatOutbox());
    final sub = c.listen(messagesProvider('c-main'), (_, _) {});
    addTearDown(sub.close);
    await c.read(messagesProvider('c-main').future);
    final chat = c.read(messagesProvider('c-main').notifier);
    await chat.send(body: 'Partita alle 22');
    await tester.pump();
    final waiting = _mine(c).single;
    expect(waiting.waiting, isTrue);

    repo.offline = false;
    final report = await chat.retry(waiting.id);
    expect(report.error, isNull);
    expect(report.waiting, isFalse);
    expect(repo.sent, ['Partita alle 22']);
    await tester.pump();
    expect(_mine(c).single.isLocal, isFalse);
  });

  testWidgets('App chiusa con un messaggio in uscita: alla riapertura parte da '
      'solo, anche senza aprire la conversazione', (tester) async {
    final repo = _OfflineRepository()..offline = true;
    final outbox = MemoryChatOutbox();

    // Prima volta: niente rete, poi l'app si chiude.
    final before = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatOutboxProvider.overrideWithValue(outbox),
        currentUserIdProvider.overrideWith((ref) => 'demo'),
      ],
    );
    final sub = before.listen(messagesProvider('c-main'), (_, _) {});
    await before.read(messagesProvider('c-main').future);
    await before
        .read(messagesProvider('c-main').notifier)
        .send(body: 'Ci sono');
    sub.close();
    before.dispose();
    expect(repo.sent, isEmpty);
    expect(await outbox.pending('demo'), hasLength(1));

    // Riaperta con la rete: parte appena entrati, senza aprire la chat.
    repo.offline = false;
    final after = _container(repo, outbox);
    after.read(chatOutboxResumerProvider);
    await tester.pump();
    await tester.pump();
    expect(after.exists(messagesProvider('c-main')), isTrue);
    expect(repo.sent, ['Ci sono']);
    expect(await outbox.pending('demo'), isEmpty);
    // Partito: la conversazione, non più trattenuta, viene liberata.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Un messaggio rifiutato dal server non riparte da solo: resta '
      '"non inviato" da riprovare o togliere (anche dal telefono)', (
    tester,
  ) async {
    final repo = _OfflineRepository();
    final outbox = MemoryChatOutbox();
    final c = _container(repo, outbox);
    final sub = c.listen(messagesProvider('c-main'), (_, _) {});
    addTearDown(sub.close);
    await c.read(messagesProvider('c-main').future);
    final chat = c.read(messagesProvider('c-main').notifier);

    // Risposta a un messaggio che non è di questo canale: il database la rifiuta.
    final report = await chat.send(body: 'Fuori posto', replyTo: 'm3');
    expect(report.error, isNotNull);
    expect(report.waiting, isFalse);
    await tester.pump();
    final failed = _mine(c).single;
    expect(failed.failed, isTrue);
    await tester.pump(const Duration(minutes: 1));
    expect(repo.sent, isEmpty);

    chat.discard(failed.id);
    await tester.pump();
    expect(_mine(c), isEmpty);
    expect(await outbox.pending('demo'), isEmpty);
  });
}
