import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio/just_audio.dart';
import 'package:milanac/core/audio_focus.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/features/chat/channel_messages.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/chat/voice_player.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/link_text.dart';

import 'helpers.dart';

/// Registratore finto: il test decide quando parte e se c'è il permesso.
class FakeVoiceRecorder implements VoiceRecorder {
  bool permission = true;

  /// Avvio lento (dialogo del permesso, cartella, encoder): parte quando il test
  /// completa [pendingStart].
  bool slowStart = false;
  Completer<bool>? pendingStart;
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  /// Il permesso è stato chiesto (dialogo del sistema).
  bool askedPermission = false;
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission({bool request = false}) async {
    if (request) askedPermission = true;
    return permission;
  }

  @override
  Future<bool> start({bool requestPermission = true}) async {
    starts++;
    if (requestPermission) askedPermission = true;
    if (!permission) return false;
    if (slowStart) {
      pendingStart = Completer<bool>();
      if (!await pendingStart!.future) return false;
    }
    _recording = true;
    return true;
  }

  @override
  Future<({Uint8List bytes, int seconds, String path})?> stop({
    int maxSeconds = maxVoiceSeconds,
    bool keepFile = false,
  }) async {
    stops++;
    if (!_recording) return null;
    _recording = false;
    return (
      bytes: Uint8List.fromList(List.filled(800, 1)),
      seconds: 3,
      path: 'vocale.m4a',
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _recording = false;
  }

  @override
  void dispose() {}
}

/// Lettore finto dei vocali: [failLoad] fa fallire il caricamento.
class FakeAudioPlayer extends Fake implements AudioPlayer {
  final _states = StreamController<PlayerState>.broadcast();
  bool failLoad = false;
  bool _playing = false;
  int pauses = 0;

  @override
  bool get playing => _playing;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    if (failLoad) throw Exception('link scaduto');
    return const Duration(seconds: 12);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauses++;
    _playing = false;
    _states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _states.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<void> dispose() async {}
}

/// La lettura dell'ultima volta non si carica (rete): il canale si segna letto lo stesso.
class _LastReadFailsRepository extends DemoChatRepository {
  @override
  Future<DateTime?> lastReadAt(String channelId) async =>
      throw Exception('rete assente');

  Future<DateTime?> savedRead(String channelId) => super.lastReadAt(channelId);
}

/// Il tempo reale può cadere: [fail] manda un errore allo stream dei messaggi aperto.
class _FlakyRepository extends DemoChatRepository {
  _FlakyRepository({super.messages});
  final _errors = StreamController<Object>.broadcast();
  int streams = 0;

  void fail() => _errors.add(Exception('tempo reale caduto'));

  @override
  Stream<List<ChatMessage>> watchMessages(String channelId) {
    streams++;
    final subs = <StreamSubscription<Object?>>[];
    late final StreamController<List<ChatMessage>> out;
    out = StreamController(
      onListen: () => subs
        ..add(
          super
              .watchMessages(channelId)
              .listen(out.add, onError: out.addError),
        )
        ..add(_errors.stream.listen(out.addError)),
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return out.stream;
  }
}

/// Conta quante volte si chiedono i canali (per il cambio di account).
class _CountingRepository extends DemoChatRepository {
  int channelRequests = 0;

  @override
  Stream<List<Channel>> watchChannels() {
    channelRequests++;
    return super.watchChannels();
  }
}

class _Account extends Notifier<String?> {
  @override
  String? build() => 'demo';

  void set(String? id) => state = id;
}

final _accountProvider = NotifierProvider<_Account, String?>(_Account.new);

/// L'app demo con la chat [repo] (quella di esempio se manca) e il registratore finto.
Future<ProviderContainer> startChat(
  WidgetTester tester, {
  ChatRepository? repo,
  FakeVoiceRecorder? recorder,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      if (repo != null) chatRepositoryProvider.overrideWithValue(repo),
      voiceRecorderFactoryProvider.overrideWithValue(
        () => recorder ?? FakeVoiceRecorder(),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(introDoneProvider.notifier).complete();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MilanacApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> openChannel(WidgetTester tester, String name) async {
  await goToSection(tester, 'Chat');
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// Tiene premuto il microfono per [hold] e lo rilascia.
Future<void> recordVoice(WidgetTester tester, Duration hold) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.bySemanticsLabel('Registra un vocale')),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(hold);
  await gesture.up();
  await tester.pumpAndSettle();
}

ChannelHistory history(ProviderContainer container, String channelId) =>
    container.read(messagesProvider(channelId)).value!;

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  tearDown(() => PushService.instance.shouldShowInApp = null);

  test('link nel testo: si riconoscono http e www, la punteggiatura resta fuori', () {
    final pieces = splitLinks(
      'Guarda https://youtu.be/abc, poi www.milanac.it. Wiki: https://it.wikipedia.org/wiki/Milan_(calcio)',
    );
    expect(pieces.map((p) => p.text).toList(), [
      'Guarda ',
      'https://youtu.be/abc',
      ', poi ',
      'www.milanac.it',
      '. Wiki: ',
      'https://it.wikipedia.org/wiki/Milan_(calcio)',
    ]);
    expect(pieces.where((p) => p.isLink).length, 3);
    expect(pieces[3].uri.toString(), 'https://www.milanac.it');
    expect(splitLinks('Nessun link qui').single.isLink, isFalse);
  });

  testWidgets('Chat stile Telegram: nuovi messaggi, risposta, vocale, allegato '
      'scaduto, elimina, silenzia', (tester) async {
    final recorder = FakeVoiceRecorder();
    await startChat(tester, recorder: recorder);
    // Badge dei non letti sulla scheda Chat (2 in Generale + 1 in Milan AC).
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('3')),
      findsOneWidget,
    );
    await goToSection(tester, 'Chat');

    expect(find.text('Generale'), findsOneWidget);
    expect(find.text('Comunicazioni'), findsOneWidget);
    expect(find.text('Luca Bianchi: Ci sono 💪'), findsOneWidget);

    // Milan AC: la chat della squadra.
    await tester.tap(find.text('Milan AC'));
    await tester.pumpAndSettle();
    expect(find.text('Stasera provo la build nuova da DC'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.text('Stasera tutti in lobby alle 21:15!'), findsNWidgets(2));
    // Il separatore sopra il primo messaggio arrivato dopo l'ultima lettura.
    expect(find.text('Nuovi messaggi'), findsOneWidget);
    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Ieri'), findsOneWidget);
    // La foto di ieri è scaduta; il vocale di 12 secondi si può ascoltare.
    expect(find.text('Allegato scaduto'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    await tester.tap(find.byTooltip('Ascolta'));
    await tester.pumpAndSettle();
    expect(find.text('Vocale non disponibile nella demo.'), findsOneWidget);
    // L'avviso in basso sparisce dopo qualche secondo (copre la barra di scrittura).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // "Ci sono 💪" cita il messaggio di Marco Rossi.
    expect(find.text('Marco Rossi'), findsWidgets);

    // Rispondi con pressione lunga.
    await tester.longPress(find.text('Ci sono 💪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rispondi'));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Luca Bianchi'), findsOneWidget);
    // Senza testo c'è il microfono (tieni premuto); con il testo compare "Invia".
    // Il permesso del microfono si chiede al tocco, non durante la pressione lunga.
    expect(find.byTooltip('Invia'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Registra un vocale'));
    await tester.pumpAndSettle();
    expect(recorder.askedPermission, isTrue);
    expect(find.textContaining('Tieni premuto per registrare'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Grande!');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Grande!'), findsOneWidget);
    expect(find.text('Ci sono 💪'), findsNWidgets(2));
    expect(find.text('Rispondi a Luca Bianchi'), findsNothing);

    // Elimina (con conferma) il proprio messaggio.
    await tester.longPress(find.text('Grande!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina messaggio'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare il messaggio?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('Grande!'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Forza MILANAC!');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Forza MILANAC!'), findsOneWidget);

    await tester.tap(find.byTooltip('Silenzia canale'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Riattiva notifiche'), findsOneWidget);

    // Tornando alla lista: tutto letto, canale silenziato.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Demo Direttivo: Forza MILANAC!'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_rounded), findsOneWidget);

    // Tattiche: il link nel messaggio è cliccabile.
    await tester.tap(find.text('Tattiche & Schemi'));
    await tester.pumpAndSettle();
    expect(find.byType(LinkText), findsWidgets);
    expect(
      find.textContaining('https://youtu.be/dQw4w9WgXcQ', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('Vocale: se il dito si alza prima che il registratore parta non si '
      'registra e non parte niente da solo', (tester) async {
    final recorder = FakeVoiceRecorder()..slowStart = true;
    final container = await startChat(tester, recorder: recorder);
    await openChannel(tester, 'Generale');
    final before = history(container, 'c-main').messages.length;
    final mic = find.bySemanticsLabel('Registra un vocale');

    // Pressione lunga: il registratore è lento a partire e il dito si alza subito.
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(recorder.starts, 1);
    expect(
      recorder.askedPermission,
      isFalse,
      reason: 'durante la pressione lunga il permesso non si chiede',
    );
    await gesture.up();
    await tester.pump();
    recorder.pendingStart!.complete(true);
    await tester.pumpAndSettle();
    // Partito a dito alzato: annullato subito, niente registrazione in corso.
    expect(recorder.cancels, 1);
    expect(recorder.isRecording, isFalse);
    expect(find.text('◀ Scorri per annullare'), findsNothing);
    expect(container.read(audioFocusProvider), isEmpty);
    // Dopo più di due minuti non è partito nessun vocale.
    await tester.pump(const Duration(seconds: maxVoiceSeconds + 10));
    await tester.pumpAndSettle();
    expect(recorder.stops, 0);
    expect(history(container, 'c-main').messages, hasLength(before));

    // Lo stesso se il gesto viene interrotto (per esempio da un dialogo del sistema).
    final interrupted = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await interrupted.cancel();
    await tester.pump();
    recorder.pendingStart!.complete(true);
    await tester.pumpAndSettle();
    expect(recorder.cancels, 2);
    expect(recorder.isRecording, isFalse);

    // Registrazione normale: tenuto premuto 3 secondi, parte al rilascio.
    recorder.slowStart = false;
    final hold = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('◀ Scorri per annullare'), findsOneWidget);
    expect(
      container.read(audioFocusProvider),
      contains(AudioUse.registrazioneVocale),
    );
    await tester.pump(const Duration(seconds: 3));
    await hold.up();
    await tester.pumpAndSettle();
    expect(recorder.stops, 1);
    expect(container.read(audioFocusProvider), isEmpty);
    final sent = history(container, 'c-main').messages.first;
    expect(sent.hasAudio, isTrue);
    expect(sent.durationS, 3);
    expect(sent.isLocal, isFalse);
    expect(find.text('0:03'), findsOneWidget);

    // Senza permesso la pressione lunga non lo chiede: lo chiede il tocco.
    recorder
      ..permission = false
      ..askedPermission = false;
    await recordVoice(tester, const Duration(seconds: 2));
    expect(recorder.askedPermission, isFalse);
    expect(
      find.text('Tocca il microfono per dare il permesso di registrare.'),
      findsOneWidget,
    );
    expect(history(container, 'c-main').messages, hasLength(before + 1));
  });

  testWidgets('Eliminazioni: il messaggio eliminato da un altro sparisce dalla '
      'conversazione aperta, la citazione resta "non più disponibile"', (
    tester,
  ) async {
    final repo = DemoChatRepository();
    final container = await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    const lobby = 'Stasera tutti in lobby alle 21:15!';
    expect(find.text(lobby), findsNWidgets(2)); // il messaggio e la citazione

    // Sto rispondendo a Marco quando lui elimina il messaggio da un altro telefono.
    await tester.longPress(find.widgetWithText(LinkText, lobby));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rispondi'));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Marco Rossi'), findsOneWidget);
    repo.deleteElsewhere('m1');
    await tester.pumpAndSettle();
    expect(find.text(lobby), findsNothing);
    expect(find.text('Messaggio non più disponibile'), findsOneWidget);
    expect(find.text('Rispondi a Marco Rossi'), findsNothing);
    expect(
      find.text('Il messaggio a cui rispondevi è stato eliminato.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Lo stream del canale lo riporta a ogni novità (non sa delle eliminazioni):
    // un messaggio nuovo non lo fa tornare.
    repo.receive(
      ChatMessage(
        id: 'n1',
        channelId: 'c-main',
        authorId: 'p4',
        body: 'Eccomi anche io',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Eccomi anche io'), findsOneWidget);
    expect(find.text(lobby), findsNothing);
    expect(find.text('Messaggio non più disponibile'), findsOneWidget);

    // Un messaggio di sistema eliminato dal server (annuncio delle carte rifatto).
    repo.receive(
      ChatMessage(
        id: 'carte',
        channelId: 'c-main',
        isSystem: true,
        body: 'Carte speciali della giornata',
        meta: const {'type': 'special_cards'},
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Carte speciali della giornata'), findsOneWidget);
    repo.deleteElsewhere('carte');
    await tester.pumpAndSettle();
    expect(find.text('Carte speciali della giornata'), findsNothing);
    final ids = history(container, 'c-main').messages.map((m) => m.id);
    expect(ids, isNot(contains('m1')));
    expect(ids, isNot(contains('carte')));
  });

  testWidgets('Conversazione lunga: i messaggi precedenti arrivano a pagine '
      'scorrendo in cima, senza doppioni', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 4));
    ChatMessage numbered(int i) => ChatMessage(
      id: 'v$i',
      channelId: 'c-main',
      authorId: i.isEven ? 'p2' : 'p3',
      body: 'Messaggio $i',
      createdAt: start.add(Duration(minutes: i)),
    );
    final repo = DemoChatRepository(
      messages: [for (var i = 1; i <= 130; i++) numbered(i)],
    );
    final container = await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    var loaded = history(container, 'c-main');
    expect(loaded.messages, hasLength(chatRecentLimit));
    expect(loaded.hasMore, isTrue);
    expect(find.text('Messaggio 130'), findsOneWidget);

    // Mentre si scorre arriva un messaggio nuovo (e lo stream riporta tutti gli altri).
    repo.receive(numbered(131));
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byKey(const ValueKey('chat-messaggi')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Messaggio 1'),
      500,
      scrollable: list,
      maxScrolls: 300,
    );
    await tester.pumpAndSettle();
    loaded = history(container, 'c-main');
    final ids = [for (final m in loaded.messages) m.id];
    expect(ids.toSet(), hasLength(ids.length), reason: 'nessun doppione');
    expect(ids, hasLength(131));
    expect(loaded.hasMore, isFalse);
    expect(ids.first, 'v131');
    expect(ids.last, 'v1');
    expect(find.text('Messaggio 1'), findsOneWidget);
    // Al confine tra i più recenti e la prima pagina il messaggio compare una volta.
    await tester.scrollUntilVisible(
      find.text('Messaggio 81'),
      -500,
      scrollable: list,
      maxScrolls: 300,
    );
    expect(find.text('Messaggio 81'), findsOneWidget);
    expect(find.text('Messaggio 82'), findsOneWidget);
  });

  testWidgets('Tempo reale caduto per un momento: la conversazione resta dov\'era, '
      'con la striscia, poi riparte', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final repo = _FlakyRepository(
      messages: [
        for (var i = 1; i <= 40; i++)
          ChatMessage(
            id: 'v$i',
            channelId: 'c-main',
            authorId: 'p2',
            body: 'Messaggio $i',
            createdAt: start.add(Duration(minutes: i)),
          ),
      ],
    );
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    final list = find.descendant(
      of: find.byKey(const ValueKey('chat-messaggi')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(list, const Offset(0, 700));
    await tester.pumpAndSettle();
    double offset() => tester.state<ScrollableState>(list).position.pixels;
    final before = offset();
    expect(before, greaterThan(300));
    final shown = tester
        .widgetList<Text>(find.textContaining('Messaggio '))
        .first
        .data!;

    repo.fail();
    await tester.pump();
    await tester.pump();
    expect(find.text('Connessione persa: riprovo…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(shown), findsOneWidget);
    expect(offset(), before);

    // Il nuovo tentativo riapre lo stream: la striscia sparisce, il punto resta.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.streams, 2);
    expect(find.text('Connessione persa: riprovo…'), findsNothing);
    expect(offset(), before);
  });

  test('meta malformato: il messaggio si legge lo stesso', () {
    const row = {
      'id': 'x1',
      'channel_id': 'c-main',
      'kind': 'system',
      'body': 'Formazione pubblicata',
      'created_at': '2026-10-12T10:00:00.123456+00:00',
    };
    for (final meta in ['testo', 42, const [1, 2], null]) {
      final m = ChatMessage.fromMap({...row, 'meta': meta});
      expect(m.meta, isEmpty);
      expect(m.systemType, '');
    }
    final odd = ChatMessage.fromMap({
      ...row,
      'meta': {'type': 7, 'title': 3},
    });
    expect(odd.systemType, '');
    expect(odd.replayTitle, isNull);
    expect(odd.summary, 'Formazione pubblicata');
    // Una riga senza data si scarta, senza fermare le altre.
    expect(ChatMessage.tryFromMap({...row, 'created_at': null}), isNull);
    expect(ChatMessage.tryFromMap(row)?.createdAt.microsecond, 456);
  });

  testWidgets('Replay e messaggi automatici con meta malformato: la bolla resta '
      'per tutti', (tester) async {
    final now = DateTime.now();
    final repo = DemoChatRepository(
      messages: [
        ChatMessage(
          id: 'r1',
          channelId: 'c-tattiche',
          authorId: 'p2',
          durationS: 20,
          meta: const {'type': 'replay', 'title': 42, 'board': 'rotta'},
          createdAt: now.subtract(const Duration(minutes: 30)),
        ),
        ChatMessage(
          id: 'r2',
          channelId: 'c-tattiche',
          authorId: 'p2',
          durationS: 20,
          meta: const {
            'type': 'replay',
            'title': 'Pressing alto',
            'board': {
              'tokens': [
                {'id': 5, 'x': 'a'},
              ],
              'arrows': 'nessuna',
            },
          },
          createdAt: now.subtract(const Duration(minutes: 20)),
        ),
        // Coordinate enormi: senza controllo il disegno della freccia non finirebbe.
        ChatMessage(
          id: 'r3',
          channelId: 'c-tattiche',
          authorId: 'p3',
          meta: const {
            'type': 'replay',
            'board': {
              'arrows': [
                {'x1': 0, 'y1': 0, 'x2': 1e300, 'y2': -1e300, 'd': true},
              ],
              'tokens': [
                {'id': 't', 'x': 2.5, 'y': -4, 'l': '9'},
              ],
            },
          },
          createdAt: now.subtract(const Duration(minutes: 10)),
        ),
        ChatMessage(
          id: 's1',
          channelId: 'c-tattiche',
          isSystem: true,
          body: 'Formazione pubblicata',
          meta: const {'type': 99},
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1080, 4000);
    await startChat(tester, repo: repo);
    tester.view.physicalSize = const Size(1080, 4000);
    await openChannel(tester, 'Tattiche & Schemi');
    expect(tester.takeException(), isNull);
    expect(find.text('SCHEMA CON AUDIO'), findsNWidgets(3));
    expect(find.text('Schema'), findsNWidgets(2));
    expect(find.text('Pressing alto'), findsOneWidget);
    expect(find.text('Formazione pubblicata'), findsOneWidget);
  });

  testWidgets('Risposta a un messaggio eliminato nel frattempo: il vocale parte '
      'senza citazione invece di perdersi', (tester) async {
    final repo = DemoChatRepository();
    final container = await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    await tester.longPress(find.widgetWithText(LinkText, 'Ci sono 💪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rispondi'));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Luca Bianchi'), findsOneWidget);

    // Luca elimina il messaggio, ma al telefono l'eliminazione non arriva.
    repo.deleteElsewhere('m2', realtime: false);
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Luca Bianchi'), findsOneWidget);
    await recordVoice(tester, const Duration(seconds: 3));
    expect(
      find.text('Il messaggio citato è stato eliminato: inviato senza citazione.'),
      findsOneWidget,
    );
    expect(find.text('Rispondi a Luca Bianchi'), findsNothing);
    final voice = history(container, 'c-main').messages.first;
    expect(voice.hasAudio, isTrue);
    expect(voice.replyTo, isNull);
    expect(voice.isLocal, isFalse);
    expect(await repo.message(voice.id), isNotNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Lo stesso con un testo (citazione di un messaggio eliminato, senza saperlo).
    await tester.longPress(find.widgetWithText(LinkText, 'Il gol di ieri 🔥'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rispondi'));
    await tester.pumpAndSettle();
    repo.deleteElsewhere('m5', realtime: false);
    await tester.enterText(find.byType(TextField), 'Che gol!');
    await tester.pump();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    final text = history(container, 'c-main').messages.first;
    expect(text.body, 'Che gol!');
    expect(text.replyTo, isNull);
    expect(text.isLocal, isFalse);
    expect(find.text('Che gol!'), findsOneWidget);
  });

  testWidgets('Lettura: segnata con l\'ora del messaggio più recente anche se '
      'l\'ultima lettura non si carica', (tester) async {
    final repo = _LastReadFailsRepository();
    final container = await startChat(tester, repo: repo);
    final overview = container.listen(chatOverviewProvider, (_, _) {});
    addTearDown(overview.close);
    await tester.pumpAndSettle();
    expect(container.read(chatOverviewProvider).value!['c-main']!.unread, 2);
    await openChannel(tester, 'Generale');
    final newest = history(container, 'c-main').messages.first;
    expect(await repo.savedRead('c-main'), newest.createdAt);
    expect(container.read(chatOverviewProvider).value!['c-main']!.unread, 0);
  });

  testWidgets('Da un canale all\'altro con router.go: avvisi in app giusti; '
      'canale inesistente con uscita', (tester) async {
    final container = await startChat(tester);
    await openChannel(tester, 'Generale');
    bool? shows(String channel) =>
        PushService.instance.shouldShowInApp?.call({'channel': channel});
    expect(shows('main'), isFalse);
    final router = container.read(routerProvider);
    router.go('/chat/milanac');
    await tester.pumpAndSettle();
    expect(find.text('Stasera provo la build nuova da DC'), findsOneWidget);
    expect(shows('milanac'), isFalse, reason: 'il filtro del canale aperto');
    expect(shows('main'), isTrue);
    // Stessa pagina riusata dal router per un altro canale: si riparte da zero.
    router.go('/chat/tattiche');
    await tester.pumpAndSettle();
    expect(find.text('TATTICHE & SCHEMI'), findsOneWidget);
    expect(shows('tattiche'), isFalse);
    expect(shows('milanac'), isTrue);

    router.go('/chat/inesistente');
    await tester.pumpAndSettle();
    expect(find.text('Canale non disponibile'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(PushService.instance.shouldShowInApp, isNull);
    await tester.tap(find.text('Torna alla chat'));
    await tester.pumpAndSettle();
    expect(find.text('Generale'), findsOneWidget);
  });

  test('Vocali: se il caricamento fallisce si può riprovare; l\'audio passa a '
      'chi lo prende', () async {
    final player = FakeAudioPlayer()..failLoad = true;
    final container = ProviderContainer(
      overrides: [
        voiceAudioPlayerFactoryProvider.overrideWithValue(() => player),
      ],
    );
    addTearDown(container.dispose);
    container.listen(voicePlayerProvider, (_, _) {});
    final voice = container.read(voicePlayerProvider.notifier);
    final focus = container.read(audioFocusProvider.notifier);
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    // Link scaduto: errore, ma il lettore torna libero.
    await expectLater(voice.toggle('m4', 'https://chat/a.m4a'), throwsException);
    expect(container.read(voicePlayerProvider).playingId, isNull);
    expect(container.read(audioFocusProvider), isEmpty);

    // Nuovo tentativo: suona e tiene l'audio dell'app (la musica aspetta).
    player.failLoad = false;
    await voice.toggle('m4', 'https://chat/a.m4a');
    await settle();
    expect(container.read(voicePlayerProvider).playingId, 'm4');
    expect(container.read(voicePlayerProvider).playing, isTrue);
    expect(container.read(audioFocusProvider), {AudioUse.vocale});

    // Parte una registrazione: il vocale va in pausa da solo.
    focus.claim(AudioUse.registrazioneVocale);
    await settle();
    expect(player.pauses, 1);
    expect(container.read(voicePlayerProvider).playing, isFalse);
    expect(container.read(audioFocusProvider), {AudioUse.registrazioneVocale});
    focus.release(AudioUse.registrazioneVocale);

    // Riprende e poi la pausa dell'utente libera l'audio.
    await voice.toggle('m4', 'https://chat/a.m4a');
    await settle();
    expect(container.read(audioFocusProvider), {AudioUse.vocale});
    await voice.toggle('m4', 'https://chat/a.m4a');
    await settle();
    expect(container.read(voicePlayerProvider).playing, isFalse);
    expect(container.read(audioFocusProvider), isEmpty);
  });

  test('Cambio di account: canali, non letti, silenziati e messaggi si '
      'ricaricano', () async {
    final repo = _CountingRepository();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((ref) => ref.watch(_accountProvider)),
      ],
    );
    addTearDown(container.dispose);
    final subs = [
      container.listen(channelsProvider, (_, _) {}),
      container.listen(chatOverviewProvider, (_, _) {}),
      container.listen(mutedChannelsProvider, (_, _) {}),
      container.listen(messagesProvider('c-main'), (_, _) {}),
    ];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });
    await container.read(channelsProvider.future);
    await container.read(messagesProvider('c-main').future);
    expect(repo.channelRequests, 1);
    expect(container.read(channelsProvider).value, isNotEmpty);

    // Esce: niente canali né non letti del precedente.
    container.read(_accountProvider.notifier).set(null);
    await container.read(channelsProvider.future);
    expect(container.read(channelsProvider).value, isEmpty);
    expect(await container.read(chatOverviewProvider.future), isEmpty);
    expect(await container.read(mutedChannelsProvider.future), isEmpty);
    expect(
      (await container.read(messagesProvider('c-main').future)).messages,
      isEmpty,
    );

    // Entra un altro account: tutto si chiede di nuovo.
    container.read(_accountProvider.notifier).set('p2');
    await container.read(channelsProvider.future);
    expect(repo.channelRequests, 2);
    expect(
      (await container.read(messagesProvider('c-main').future)).messages,
      isNotEmpty,
    );
  });
}
