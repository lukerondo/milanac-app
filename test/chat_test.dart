import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio/just_audio.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/audio_focus.dart';
import 'package:milanac/core/auth/profile.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/push/push_service.dart';
import 'package:milanac/core/router.dart';
import 'package:milanac/core/theme.dart';
import 'package:milanac/features/chat/channel_messages.dart';
import 'package:milanac/features/chat/channel_page.dart';
import 'package:milanac/features/chat/chat_list_page.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/chat/chat_widgets.dart';
import 'package:milanac/features/chat/voice_player.dart';
import 'package:milanac/features/chat/voice_recorder.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/main.dart';
import 'package:milanac/shared/async_view.dart';
import 'package:milanac/shared/gold_loader.dart';
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

/// Lettore finto dei vocali: [failLoad] fa fallire il caricamento; con [slow] il
/// caricamento aspetta [finishLoad] e, come in just_audio, uno stop o un altro
/// caricamento lo interrompono.
class FakeAudioPlayer extends Fake implements AudioPlayer {
  final _states = StreamController<PlayerState>.broadcast();
  bool failLoad = false;
  bool slow = false;
  Completer<void>? _loading;
  bool _playing = false;
  int pauses = 0;

  /// Gli indirizzi caricati fino in fondo.
  final loaded = <String>[];

  void finishLoad() => _loading?.complete();

  void _interrupt() {
    final loading = _loading;
    _loading = null;
    if (loading != null && !loading.isCompleted) {
      loading.completeError(PlayerInterruptedException('Loading interrupted'));
    }
  }

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
    _interrupt();
    if (slow) {
      final loading = _loading = Completer<void>();
      await loading.future;
    }
    if (failLoad) throw Exception('link scaduto');
    loaded.add(url);
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
    _interrupt();
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
          super.watchMessages(channelId).listen(out.add, onError: out.addError),
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

/// Riconnessioni del tempo reale: i messaggi arrivati mentre era caduto
/// (`receive(..., realtime: false)`) li porta solo lo stream nuovo; le pagine
/// precedenti possono non arrivare ([olderFail]); le letture si registrano.
class _ReconnectingRepository extends _FlakyRepository {
  _ReconnectingRepository({super.messages});
  bool olderFail = false;
  final readUntil = <DateTime?>[];

  @override
  Future<List<ChatMessage>> olderMessages(
    String channelId,
    DateTime before, {
    int limit = chatPageSize,
  }) async {
    if (olderFail) throw Exception('rete assente');
    return super.olderMessages(channelId, before, limit: limit);
  }

  @override
  Future<void> markRead(String channelId, {DateTime? until}) {
    readUntil.add(until);
    return super.markRead(channelId, until: until);
  }
}

/// Invio lento ([gate]) che può fallire ([failSend]).
class _SlowSendRepository extends DemoChatRepository {
  Completer<void>? gate;
  bool failSend = false;

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
    final wait = gate?.future;
    if (wait != null) await wait;
    if (failSend) throw Exception('rete assente');
    return super.send(
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
  }
}

/// I link dei vocali si contano; senza rete ([offline]) non arrivano.
class _AudioLinksRepository extends DemoChatRepository {
  int links = 0;
  bool offline = false;

  @override
  Future<String> audioUrl(String path) async {
    if (offline) throw Exception('rete assente');
    links++;
    return 'https://chat/$path';
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
  List<Override> overrides = const [],
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
      ...overrides,
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

/// Il pulsante del microfono (tavola 13).
const micLabel = 'Tieni premuto per registrare un vocale';

/// Apre "Cerca nei messaggi" dalla scheda Chat: dal pulsante nella barra in alto se
/// c'è, altrimenti come fa il pulsante.
Future<void> openSearch(WidgetTester tester) async {
  await goToSection(tester, 'Chat');
  final button = find.byTooltip('Cerca nei messaggi');
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
  } else {
    unawaited(showChatSearch(tester.element(find.byType(ChatListPage))));
  }
  await tester.pumpAndSettle();
}

/// Scrive [text] nella ricerca e aspetta che parta.
Future<void> searchFor(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Tiene premuto il microfono per [hold] e lo rilascia.
Future<void> recordVoice(WidgetTester tester, Duration hold) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.bySemanticsLabel(micLabel)),
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

  test(
    'link nel testo: si riconoscono http e www, la punteggiatura resta fuori',
    () {
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
    },
  );

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
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.text('Stasera tutti in lobby alle 21:15!'), findsNWidgets(2));
    // Il separatore sopra il primo messaggio arrivato dopo l'ultima lettura.
    expect(find.text('Nuovi messaggi'), findsOneWidget);
    expect(find.text('Oggi'), findsOneWidget);
    expect(find.text('Ieri'), findsOneWidget);
    // La foto di ieri è scaduta; il vocale di 12 secondi si può ascoltare.
    expect(find.text('Foto scaduta'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    await tester.tap(find.byTooltip('Ascolta il vocale'));
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
    await tester.tap(find.bySemanticsLabel(micLabel));
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

    await tester.tap(find.byTooltip('Silenzia il canale'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Riattiva le notifiche'), findsOneWidget);

    // Tornando alla lista: tutto letto, canale silenziato.
    await tester.tap(find.byTooltip('Indietro'));
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

  testWidgets(
    'Vocale: se il dito si alza prima che il registratore parta non si '
    'registra e non parte niente da solo',
    (tester) async {
      final recorder = FakeVoiceRecorder()..slowStart = true;
      final container = await startChat(tester, recorder: recorder);
      await openChannel(tester, 'Generale');
      final before = history(container, 'c-main').messages.length;
      final mic = find.bySemanticsLabel(micLabel);

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
    },
  );

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

  testWidgets(
    'Tempo reale caduto per un momento: la conversazione resta dov\'era, '
    'con la striscia, poi riparte',
    (tester) async {
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
      expect(find.byType(GoldLoader), findsNothing);
      expect(find.text(shown), findsOneWidget);
      expect(offset(), before);

      // Il nuovo tentativo riapre lo stream: la striscia sparisce, il punto resta.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(repo.streams, 2);
      expect(find.text('Connessione persa: riprovo…'), findsNothing);
      expect(offset(), before);
    },
  );

  test('meta malformato: il messaggio si legge lo stesso', () {
    const row = {
      'id': 'x1',
      'channel_id': 'c-main',
      'kind': 'system',
      'body': 'Formazione pubblicata',
      'created_at': '2026-10-12T10:00:00.123456+00:00',
    };
    for (final meta in [
      'testo',
      42,
      const [1, 2],
      null,
    ]) {
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

  testWidgets(
    'Replay e messaggi automatici con meta malformato: la bolla resta '
    'per tutti',
    (tester) async {
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
    },
  );

  testWidgets(
    'Risposta a un messaggio eliminato nel frattempo: il vocale parte '
    'senza citazione invece di perdersi',
    (tester) async {
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
        find.text(
          'Il messaggio citato è stato eliminato: inviato senza citazione.',
        ),
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
      final yesterday = find.widgetWithText(LinkText, 'Il gol di ieri 🔥');
      await tester.scrollUntilVisible(
        yesterday,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('chat-messaggi')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(yesterday);
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
    },
  );

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
    expect(find.text('Tattiche & Schemi'), findsOneWidget);
    expect(shows('tattiche'), isFalse);
    expect(shows('milanac'), isTrue);

    router.go('/chat/inesistente');
    await tester.pumpAndSettle();
    expect(find.text('Canale non disponibile'), findsOneWidget);
    expect(find.byType(GoldLoader), findsNothing);
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
    Future<String> link() async => 'https://chat/a.m4a';

    // Link scaduto: errore, ma il lettore torna libero.
    await expectLater(voice.toggle('m4', link), throwsException);
    expect(container.read(voicePlayerProvider).playingId, isNull);
    expect(container.read(voicePlayerProvider).loading, isFalse);
    expect(container.read(audioFocusProvider), isEmpty);

    // Nuovo tentativo: suona e tiene l'audio dell'app (la musica aspetta).
    player.failLoad = false;
    await voice.toggle('m4', link);
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
    await voice.toggle('m4', link);
    await settle();
    expect(container.read(audioFocusProvider), {AudioUse.vocale});
    await voice.toggle('m4', link);
    await settle();
    expect(container.read(voicePlayerProvider).playing, isFalse);
    expect(container.read(audioFocusProvider), isEmpty);
  });

  test('Vocali: pausa e ripresa del vocale nel lettore senza chiedere il link, '
      'anche senza rete', () async {
    final player = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        voiceAudioPlayerFactoryProvider.overrideWithValue(() => player),
      ],
    );
    addTearDown(container.dispose);
    container.listen(voicePlayerProvider, (_, _) {});
    final voice = container.read(voicePlayerProvider.notifier);
    VoiceState state() => container.read(voicePlayerProvider);
    Future<void> settle() => Future<void>.delayed(Duration.zero);
    var links = 0;
    var online = true;
    Future<String> link() async {
      links++;
      if (!online) throw Exception('rete assente');
      return 'https://chat/a.m4a';
    }

    await voice.toggle('m4', link);
    await settle();
    expect(state().playing, isTrue);
    expect(links, 1);

    // Senza rete: la pausa e la ripresa arrivano subito, senza nuovi link.
    online = false;
    await voice.toggle('m4', link);
    await settle();
    expect(state().playing, isFalse);
    expect(player.pauses, 1);
    await voice.toggle('m4', link);
    await settle();
    expect(state().playing, isTrue);
    expect(links, 1);
    expect(player.loaded, ['https://chat/a.m4a']);
  });

  test(
    'Vocali: toccando un altro vocale mentre il primo arriva, il primo finisce '
    'in silenzio e non tocca il secondo',
    () async {
      final player = FakeAudioPlayer()..slow = true;
      final container = ProviderContainer(
        overrides: [
          voiceAudioPlayerFactoryProvider.overrideWithValue(() => player),
        ],
      );
      addTearDown(container.dispose);
      container.listen(voicePlayerProvider, (_, _) {});
      final voice = container.read(voicePlayerProvider.notifier);
      VoiceState state() => container.read(voicePlayerProvider);
      Future<void> settle() => Future<void>.delayed(Duration.zero);

      // Il primo si sta caricando quando si tocca il secondo: il primo è
      // interrotto, senza errori.
      Object? firstError;
      final first = voice
          .toggle('m1', () async => 'https://chat/1.m4a')
          .catchError((Object e) => firstError = e);
      await settle();
      expect(state().playingId, 'm1');
      expect(state().loading, isTrue);
      final second = voice.toggle('m2', () async => 'https://chat/2.m4a');
      await first;
      expect(firstError, isNull);
      expect(state().playingId, 'm2');
      await settle();
      player.finishLoad();
      await second;
      await settle();
      expect(state().playingId, 'm2');
      expect(state().loading, isFalse);
      expect(state().playing, isTrue);
      expect(player.loaded, ['https://chat/2.m4a']);
      expect(container.read(audioFocusProvider), {AudioUse.vocale});

      // Un link che arriva tardi non fa partire il vocale di prima.
      player.slow = false;
      final slowLink = Completer<String>();
      final third = voice.toggle('m3', () => slowLink.future);
      await settle();
      await voice.toggle('m4', () async => 'https://chat/4.m4a');
      await settle();
      slowLink.complete('https://chat/3.m4a');
      await third;
      await settle();
      expect(state().playingId, 'm4');
      expect(state().playing, isTrue);
      expect(player.loaded, ['https://chat/2.m4a', 'https://chat/4.m4a']);

      // Rete lenta: toccando di nuovo il vocale che arriva, il caricamento si
      // annulla (senza errori) e il lettore torna libero.
      player.slow = true;
      Object? cancelError;
      final cancelled = voice
          .toggle('m5', () async => 'https://chat/5.m4a')
          .catchError((Object e) => cancelError = e);
      await settle();
      expect(state().loading, isTrue);
      await voice.toggle('m5', () async => 'https://chat/5.m4a');
      await cancelled;
      await settle();
      expect(cancelError, isNull);
      expect(state().playingId, isNull);
      expect(state().loading, isFalse);
      expect(container.read(audioFocusProvider), isEmpty);
      expect(player.loaded, hasLength(2));
    },
  );

  test('Cambio di account: canali, non letti, silenziati e messaggi si '
      'ricaricano', () async {
    final repo = _CountingRepository();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(_accountProvider),
        ),
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

  testWidgets('Elenco dei canali (tavola 12): stanza aperta in cima, cuffie, '
      'non letti, descrizioni dei canali senza messaggi', (tester) async {
    await startChat(tester);
    await goToSection(tester, 'Chat');
    // La card della stanza vocale di Milan AC in cima, le cuffie accanto al nome.
    expect(find.textContaining('Stanza vocale aperta'), findsOneWidget);
    expect(find.text('Marco e Luca sono dentro'), findsOneWidget);
    // Le righe si leggono intere: nome, cuffie, ultimo messaggio, ora, non letti.
    expect(
      find.bySemanticsLabel(RegExp(r'^Milan AC\nstanza vocale aperta\n')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'\n2 non letti$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\n1 non letto$')), findsOneWidget);
    expect(find.text('Luca Bianchi: Ci sono 💪'), findsOneWidget);
    expect(find.text('La chat del Futuro'), findsOneWidget);
    expect(find.text('Avvisi ufficiali del Direttivo'), findsOneWidget);
    expect(find.text('Solo per il Direttivo'), findsOneWidget);
    // La Sala Direttivo con il lucchetto nel riquadro.
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

    // La conversazione: nome del canale e chi lo legge nella barra in alto.
    await tester.tap(find.text('Milan AC'));
    await tester.pumpAndSettle();
    expect(find.text('La squadra Milan AC'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.text('Tutto il club'), findsOneWidget);
    expect(find.text('Foto scaduta'), findsOneWidget);
    expect(find.byTooltip('Stanza vocale'), findsOneWidget);
    expect(find.byTooltip('Silenzia il canale'), findsOneWidget);
  });

  testWidgets(
    'Conversazione aperta da una notifica: indietro porta all\'elenco '
    'dei canali invece di chiudere l\'app',
    (tester) async {
      await startChat(tester);
      await goToPath(tester, '/chat/main');
      expect(find.byType(ChannelPage), findsOneWidget);
      expect(find.text('Tutto il club'), findsOneWidget);
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue, reason: 'l\'app non si chiude');
      expect(find.byType(ChannelPage), findsNothing);
      expect(find.byType(ChatListPage), findsOneWidget);
      expect(find.text('CHAT'), findsOneWidget);

      // Aperta dall'elenco invece torna indietro normalmente.
      await tester.tap(find.text('Generale'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPage), findsNothing);
      expect(find.byType(ChatListPage), findsOneWidget);
    },
  );

  test('ricerca: like letterale, pezzo di testo e parola evidenziata', () {
    expect(escapeLikePattern(r'50%_a\b'), r'50\%\_a\\b');
    expect(escapeLikePattern('lobby'), 'lobby');
    expect(searchSnippet('Ci  sono\nanche io', 'sono'), 'Ci sono anche io');
    final long = '${'parola ' * 12}e poi il gol di ieri';
    final snippet = searchSnippet(long, 'GOL');
    expect(snippet, startsWith('…'));
    expect(snippet, endsWith('il gol di ieri'));
    expect(snippet.length, lessThan(long.length));
    final spans = highlightMatches(
      'Stasera in LOBBY, poi lobby!',
      'lobby',
      hit: const TextStyle(fontWeight: FontWeight.w700),
    );
    expect(spans.map((s) => s.text).toList(), [
      'Stasera in ',
      'LOBBY',
      ', poi ',
      'lobby',
      '!',
    ]);
    expect(spans.where((s) => s.style != null), hasLength(2));
  });

  testWidgets(
    'Cerca nei messaggi: canale, autore e parola evidenziata; un tocco '
    'apre il canale',
    (tester) async {
      await startChat(tester);
      await openSearch(tester);
      expect(find.byType(ChatSearchPage), findsOneWidget);
      expect(find.textContaining('Scrivi almeno 2 lettere'), findsOneWidget);
      await searchFor(tester, 'l');
      expect(find.textContaining('Scrivi almeno 2 lettere'), findsOneWidget);

      // Maiuscole e minuscole non contano.
      await searchFor(tester, 'LOBBY');
      expect(find.text('1 MESSAGGIO'), findsOneWidget);
      expect(find.text('Generale'), findsOneWidget);
      expect(find.text('Marco Rossi'), findsOneWidget);
      final hit = find.textContaining(
        'Stasera tutti in lobby',
        findRichText: true,
      );
      expect(hit, findsOneWidget);
      final bold = <String>[];
      tester.widget<RichText>(hit).text.visitChildren((s) {
        if (s is TextSpan && s.style?.fontWeight == FontWeight.w700) {
          bold.add(s.text ?? '');
        }
        return true;
      });
      expect(bold, ['lobby']);

      // % e _ si cercano come lettere, non come caratteri jolly.
      await searchFor(tester, '%_');
      expect(find.text('Nessun messaggio con «%_».'), findsOneWidget);
      await searchFor(tester, 'zzz');
      expect(find.text('Nessun messaggio con «zzz».'), findsOneWidget);

      // Un tocco apre il canale; indietro si torna ai risultati.
      await searchFor(tester, 'build');
      expect(find.text('Milan AC'), findsOneWidget);
      expect(find.text('Andrea Neri'), findsOneWidget);
      await tester.tap(find.textContaining('build nuova', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPage), findsOneWidget);
      expect(find.text('La squadra Milan AC'), findsOneWidget);
      expect(find.text('Stasera provo la build nuova da DC'), findsOneWidget);
      await tester.tap(find.byTooltip('Indietro'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatSearchPage), findsOneWidget);
      expect(find.text('Andrea Neri'), findsOneWidget);
    },
  );

  testWidgets('Pulsante "Cerca nei messaggi" per la barra in alto', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [ChatSearchButton()])),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Cerca nei messaggi'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatSearchPage), findsOneWidget);
    expect(find.text('CERCA NEI MESSAGGI'), findsOneWidget);
  });

  testWidgets('Tema chiaro: elenco, conversazione e ricerca senza errori', (
    tester,
  ) async {
    final container = await startChat(tester);
    await container.read(appearanceProvider.notifier).set(Appearance.chiaro);
    await tester.pumpAndSettle();
    await goToSection(tester, 'Chat');
    expect(
      Theme.of(tester.element(find.text('Generale'))).brightness,
      Brightness.light,
    );
    expect(find.text('Luca Bianchi: Ci sono 💪'), findsOneWidget);
    expect(find.textContaining('Stanza vocale aperta'), findsOneWidget);

    // Conversazione: foto scaduta, vocale, risposta, nuovi messaggi, invio.
    await tester.tap(find.text('Generale'));
    await tester.pumpAndSettle();
    expect(find.text('Foto scaduta'), findsOneWidget);
    expect(find.text('Nuovi messaggi'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    await tester.longPress(find.widgetWithText(LinkText, 'Ci sono 💪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rispondi'));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Luca Bianchi'), findsOneWidget);
    final hold = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel(micLabel)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('◀ Scorri per annullare'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.text('0:03'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ciao a tutti');
    await tester.pump();
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    expect(find.text('Ciao a tutti'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();

    // Il replay della lavagna e Comunicazioni (sola lettura).
    await tester.tap(find.text('Tattiche & Schemi'));
    await tester.pumpAndSettle();
    expect(find.text('SCHEMA CON AUDIO'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();

    // La ricerca.
    await openSearch(tester);
    await searchFor(tester, 'lobby');
    expect(find.text('1 MESSAGGIO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Messaggi automatici: formazione (con la squadra), carte speciali e '
    'nuovo ingresso aprono la pagina nelle schede, senza schede doppie',
    (tester) async {
      final now = DateTime.now();
      final repo = DemoChatRepository(
        messages: [
          ChatMessage(
            id: 's1',
            channelId: 'c-comunicazioni',
            authorId: 'demo',
            isSystem: true,
            body: 'Formazione Milan AC Futuro (4-3-3): POR Rossi',
            meta: const {'type': 'formation', 'team': 'futuro', 'id': 'f1'},
            createdAt: now.subtract(const Duration(minutes: 30)),
          ),
          ChatMessage(
            id: 's2',
            channelId: 'c-comunicazioni',
            isSystem: true,
            body: 'Carte speciali della giornata',
            meta: const {'type': 'special_cards', 'match': 'x1'},
            createdAt: now.subtract(const Duration(minutes: 20)),
          ),
          ChatMessage(
            id: 's3',
            channelId: 'c-direttivo',
            isSystem: true,
            body: 'Mario Verdi è entrato nel club',
            meta: const {'type': 'new_member', 'member': 'p9'},
            createdAt: now.subtract(const Duration(minutes: 10)),
          ),
        ],
      );
      final container = await startChat(tester, repo: repo);
      final router = container.read(routerProvider);
      String location() =>
          router.routerDelegate.currentConfiguration.uri.toString();

      // Dall'elenco della chat, come un giocatore qualunque.
      await openChannel(tester, 'Comunicazioni');
      await tester.tap(find.textContaining('Formazione Milan AC Futuro'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(location(), '/formazione?squadra=futuro');
      expect(find.byType(ChannelPage), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('FORMAZIONE'), findsOneWidget);
      // Indietro si torna nelle schede, senza errori.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);

      await openChannel(tester, 'Comunicazioni');
      await tester.tap(find.text('Carte speciali della giornata'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(location(), '/carte-speciali');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('CARTE SPECIALI'), findsOneWidget);

      // Il nuovo ingresso nella Sala Direttivo: come gli altri, apre la Rosa.
      await openChannel(tester, 'Sala Direttivo');
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
      await tester.tap(find.text('Mario Verdi è entrato nel club'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(location(), '/rosa');
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets('Riconnessione dopo più di 50 messaggi: i mancanti si recuperano e '
      'finché mancano il canale non si segna letto', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 3));
    ChatMessage numbered(int i) => ChatMessage(
      id: 'v$i',
      channelId: 'c-main',
      authorId: 'p2',
      body: 'Messaggio $i',
      createdAt: start.add(Duration(minutes: i)),
    );
    final repo = _ReconnectingRepository(
      messages: [for (var i = 1; i <= 40; i++) numbered(i)],
    );
    final container = await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    expect(repo.readUntil.last, numbered(40).createdAt);

    // Il tempo reale cade: intanto arrivano 70 messaggi, e le pagine precedenti
    // non passano ancora.
    for (var i = 41; i <= 110; i++) {
      repo.receive(numbered(i), realtime: false);
    }
    repo.olderFail = true;
    repo.fail();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Riconnesso: arrivano gli ultimi 50, quelli in mezzo mancano ancora e non si
    // segnano letti.
    var loaded = history(container, 'c-main');
    expect(loaded.gap, isTrue);
    expect(loaded.messages.first.id, 'v110');
    expect(find.text('Messaggio 110'), findsOneWidget);
    expect(repo.readUntil.last, numbered(40).createdAt);

    // Torna la rete: alla prima novità i mancanti arrivano, poi si segna letto.
    repo.olderFail = false;
    repo.receive(numbered(111));
    await tester.pumpAndSettle();
    loaded = history(container, 'c-main');
    expect(loaded.gap, isFalse);
    final ids = [for (final m in loaded.messages) m.id];
    expect(ids.toSet(), hasLength(ids.length), reason: 'nessun doppione');
    for (var i = 41; i <= 111; i++) {
      expect(ids, contains('v$i'));
    }
    expect(repo.readUntil.last, numbered(111).createdAt);

    // Scorrendo in cima arrivano anche i più vecchi, senza buchi.
    await container.read(messagesProvider('c-main').notifier).loadMore();
    await tester.pumpAndSettle();
    loaded = history(container, 'c-main');
    expect(loaded.messages, hasLength(111));
    expect(loaded.hasMore, isFalse);
  });

  testWidgets('Buco dopo una riconnessione con le pagine che non arrivano: '
      'si riprova da solo, senza aspettare una novità', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 3));
    ChatMessage numbered(int i) => ChatMessage(
      id: 'v$i',
      channelId: 'c-main',
      authorId: 'p2',
      body: 'Messaggio $i',
      createdAt: start.add(Duration(minutes: i)),
    );
    final repo = _ReconnectingRepository(
      messages: [for (var i = 1; i <= 40; i++) numbered(i)],
    );
    final container = await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');

    for (var i = 41; i <= 110; i++) {
      repo.receive(numbered(i), realtime: false);
    }
    repo.olderFail = true;
    repo.fail();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(history(container, 'c-main').gap, isTrue);

    // La rete torna, ma nel canale non scrive nessuno: il recupero riparte da solo.
    repo.olderFail = false;
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    final loaded = history(container, 'c-main');
    expect(loaded.gap, isFalse);
    final ids = {for (final m in loaded.messages) m.id};
    for (var i = 41; i <= 110; i++) {
      expect(ids, contains('v$i'));
    }
    expect(repo.readUntil.last, numbered(110).createdAt);
  });

  testWidgets(
    'Uscita dalla conversazione mentre il messaggio parte: se non parte '
    'lo si dice, e al ritorno è lì da riprovare',
    (tester) async {
      final repo = _SlowSendRepository();
      final container = await startChat(tester, repo: repo);
      await openChannel(tester, 'Generale');
      final gate = repo.gate = Completer<void>();
      repo.failSend = true;
      await tester.enterText(
        find.byType(TextField),
        'Arrivo tra cinque minuti',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Invia'));
      await tester.pump();
      await tester.tap(find.byTooltip('Indietro'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPage), findsNothing);
      // La conversazione resta in memoria finché il messaggio è in sospeso.
      expect(container.exists(messagesProvider('c-main')), isTrue);

      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Messaggio in Generale non inviato'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      // Riaperta: il messaggio è lì, "non inviato"; toccandolo parte.
      await tester.tap(find.text('Generale'));
      await tester.pumpAndSettle();
      expect(find.text('Arrivo tra cinque minuti'), findsOneWidget);
      expect(find.text('Non inviato · tocca per riprovare'), findsOneWidget);
      repo
        ..gate = null
        ..failSend = false;
      await tester.tap(find.text('Arrivo tra cinque minuti'));
      await tester.pumpAndSettle();
      expect(find.text('Non inviato · tocca per riprovare'), findsNothing);
      final sent = history(container, 'c-main').messages.first;
      expect(sent.isLocal, isFalse);
      expect((await repo.message(sent.id))?.body, 'Arrivo tra cinque minuti');

      // Niente più in sospeso: uscendo la conversazione non resta in memoria.
      await tester.tap(find.byTooltip('Indietro'));
      await tester.pumpAndSettle();
      expect(container.exists(messagesProvider('c-main')), isFalse);
    },
  );

  testWidgets('Comunicazioni: chi non è del Direttivo non vede "Rispondi"', (
    tester,
  ) async {
    final repo = DemoChatRepository(
      messages: [
        ChatMessage(
          id: 'a1',
          channelId: 'c-comunicazioni',
          authorId: 'p2',
          body: 'Allenamento spostato alle 21:30',
          meta: const {'type': 'announcement'},
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    await startChat(
      tester,
      repo: repo,
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
    await openChannel(tester, 'Comunicazioni');
    expect(find.textContaining('Qui scrive solo il Direttivo'), findsOneWidget);
    await tester.longPress(find.text('Allenamento spostato alle 21:30'));
    await tester.pumpAndSettle();
    expect(find.text('Copia testo'), findsOneWidget);
    expect(find.text('Rispondi'), findsNothing);
  });

  testWidgets(
    'Vocale nella conversazione: pausa e ripresa anche senza rete, il '
    'link si chiede una volta',
    (tester) async {
      final repo = _AudioLinksRepository();
      final player = FakeAudioPlayer();
      final container = await startChat(
        tester,
        repo: repo,
        overrides: [
          voiceAudioPlayerFactoryProvider.overrideWithValue(() => player),
        ],
      );
      await openChannel(tester, 'Generale');
      await tester.tap(find.byTooltip('Ascolta il vocale'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Metti in pausa'), findsOneWidget);
      expect(repo.links, 1);
      expect(player.loaded, ['https://chat/demo/voce.m4a']);

      repo.offline = true;
      await tester.tap(find.byTooltip('Metti in pausa'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ascolta il vocale'), findsOneWidget);
      await tester.tap(find.byTooltip('Ascolta il vocale'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Metti in pausa'), findsOneWidget);
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'nessun errore di rete',
      );
      expect(repo.links, 1);
      expect(player.loaded, hasLength(1));
      // Il link resta in memoria (con il rinnovo dopo 5 ore): si chiude tutto qui.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets('Foto in chat: nella bolla decodificata alla larghezza mostrata, a '
      'schermo intero intera', (tester) async {
    // Un pixel PNG: basta per il decodificatore.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );
    final repo = DemoChatRepository(
      messages: [
        ChatMessage(
          id: 'f1',
          channelId: 'c-main',
          authorId: 'p2',
          localImage: png,
          createdAt: DateTime.now(),
        ),
      ],
    );
    await startChat(tester, repo: repo);
    await openChannel(tester, 'Generale');
    final inBubble = find.byWidgetPredicate(
      (w) => w is Image && w.image is ResizeImage,
    );
    expect(inBubble, findsOneWidget);
    // Alla larghezza in cui si vede (in pixel veri), non meno (sarebbe sfocata) e
    // poco di più.
    final width = (tester.widget<Image>(inBubble).image as ResizeImage).width!;
    final shown = tester.getSize(inBubble).width * 3;
    expect(width, greaterThanOrEqualTo(shown.round()));
    expect(width, lessThanOrEqualTo(shown * 1.05));

    // Il tocco sulla foto (nei test la foto non si decodifica: niente altezza).
    tester
        .widget<GestureDetector>(
          find
              .ancestor(of: inBubble, matching: find.byType(GestureDetector))
              .first,
        )
        .onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byWidgetPredicate(
          (w) => w is Image && w.image is MemoryImage,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Striscia "Connessione persa": testo e "Riprova" leggibili nei due '
    'temi',
    (tester) async {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
      }

      for (final brightness in Brightness.values) {
        final values = StreamController<int>();
        final provider = StreamProvider<int>(
          (ref) => values.stream,
          retry: (_, _) => null,
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: buildTheme(brightness),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => AsyncView<int>(
                    value: ref.watch(provider),
                    onRetry: () {},
                    // Come le liste delle pagine: tutto lo spazio.
                    data: (n) => ListView(children: [Text('Dato $n')]),
                  ),
                ),
              ),
            ),
          ),
        );
        values.add(1);
        await tester.pump();
        values.addError(Exception('rete assente'));
        await tester.pump();
        expect(find.text('Dato 1'), findsOneWidget);
        expect(find.text('Dati non aggiornati'), findsOneWidget);
        final strip = tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.byIcon(Icons.wifi_off_rounded),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        Color colorOf(Finder text) => tester
            .widget<RichText>(
              find.descendant(of: text, matching: find.byType(RichText)),
            )
            .text
            .style!
            .color!;
        expect(
          contrast(colorOf(find.byType(TextButton)), strip),
          greaterThanOrEqualTo(4.5),
          reason: 'Riprova nel tema $brightness',
        );
        expect(
          contrast(colorOf(find.text('Dati non aggiornati')), strip),
          greaterThanOrEqualTo(4.5),
        );
        await values.close();
      }
    },
  );
}
