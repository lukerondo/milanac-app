import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/audio_focus.dart';
import 'package:milanac/core/auth/providers.dart';
import 'package:milanac/core/push/device_tokens.dart';
import 'package:milanac/features/chat/chat_repository.dart';
import 'package:milanac/features/voce/voice_call.dart';
import 'package:milanac/features/voce/voice_engine.dart';
import 'package:milanac/features/voce/voice_foreground.dart';
import 'package:milanac/features/voce/voice_models.dart';
import 'package:milanac/features/voce/voice_repository.dart';
import 'package:milanac/features/voce/voice_room_sheet.dart';

import 'helpers.dart';
import 'home_test.dart';

/// Titolo della card della stanza di Milan AC (il nome del canale non va a capo).
const _cardMilan = 'Stanza vocale aperta · Milan AC';

const _generale = Channel(id: 'c-main', slug: 'main', name: 'Generale');
const _tattiche = Channel(
  id: 'c-tattiche',
  slug: 'tattiche',
  name: 'Tattiche & Schemi',
);

/// Stanze demo che contano i segni di vita e le stanze seguite, possono restare
/// senza rete e tenere in sospeso l'ingresso e l'uscita sul server.
class _TestRepo extends DemoVoiceRepository {
  var beats = 0;
  var roomStreams = 0;
  var offline = false;
  Completer<void>? slowJoin;
  Completer<void>? slowLeave;

  /// Le proprie sessioni aperte.
  List<VoiceSession> get mine =>
      sessions.where((s) => s.userId == 'demo' && s.isActive).toList();

  @override
  Stream<List<VoiceRoom>> watchOpenRooms() {
    roomStreams++;
    return super.watchOpenRooms();
  }

  @override
  Future<String> join(String roomId, int agoraUid) async {
    final wait = slowJoin?.future;
    if (wait != null) await wait;
    return super.join(roomId, agoraUid);
  }

  @override
  Future<void> leave(String sessionId) async {
    final wait = slowLeave?.future;
    if (wait != null) await wait;
    return super.leave(sessionId);
  }

  @override
  Future<bool> heartbeat(String sessionId, {required bool muted}) async {
    beats++;
    if (offline) throw TimeoutException('rete assente');
    return super.heartbeat(sessionId, muted: muted);
  }
}

/// L'avviso fisso (servizio in primo piano su Android), registrato.
class _TestForeground implements VoiceForeground {
  final calls = <String>[];

  /// Android l'ha rifiutato dentro il servizio dopo aver accettato l'avvio (o
  /// l'ha fermato): finché non riparte non è attivo.
  bool refused = false;
  var bluetoothAsks = 0;

  /// Il dialogo del permesso Bluetooth resta aperto finché il test non lo chiude.
  Completer<void>? bluetoothDialog;

  bool get running => calls.isNotEmpty && calls.last != 'stop';

  @override
  Future<bool> start(String channelName) async {
    calls.add('start #$channelName');
    refused = false;
    return true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<bool> isRunning() async => running && !refused;

  @override
  Future<void> askBluetooth() async {
    bluetoothAsks++;
    await bluetoothDialog?.future;
  }
}

class _Account extends Notifier<String?> {
  @override
  String? build() => 'demo';

  void set(String? id) => state = id;
}

final _accountProvider = NotifierProvider<_Account, String?>(_Account.new);

/// La propria chiamata con motori demo controllabili.
class _Call {
  _Call() {
    container = ProviderContainer(
      overrides: [
        voiceRepositoryProvider.overrideWithValue(repo),
        voiceEngineFactoryProvider.overrideWithValue(_newEngine),
        voiceForegroundProvider.overrideWithValue(foreground),
      ],
    );
  }

  late final ProviderContainer container;
  final repo = _TestRepo();
  final foreground = _TestForeground();
  final engines = <DemoVoiceEngine>[];

  /// La prossima join del motore resta in sospeso finché non si completa.
  Completer<void>? slowJoin;

  DemoVoiceEngine _newEngine() {
    final engine = DemoVoiceEngine(connecting: slowJoin?.future);
    slowJoin = null;
    engines.add(engine);
    return engine;
  }

  VoiceCall get notifier => container.read(voiceCallProvider.notifier);
  VoiceCallState get state => container.read(voiceCallProvider);
  Set<AudioUse> get focus => container.read(audioFocusProvider);
}

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('numero utente Agora: stabile, positivo e diverso tra profili', () {
    expect(agoraUidFor('demo'), agoraUidFor('demo'));
    expect(agoraUidFor('demo'), greaterThan(0));
    expect(agoraUidFor('p2'), isNot(agoraUidFor('p3')));
    expect(
      agoraUidFor('4f1c9a3e-0000-4000-8000-0000000000e1'),
      lessThan(1 << 31),
    );
  });

  testWidgets('Stanza vocale: card nella chat, stanza a schermo intero, '
      'microfono, riduci a striscia, esci; apri una stanza nuova', (
    tester,
  ) async {
    final container = await startAppAt(tester, todayAt(17));
    await goToPath(tester, '/chat/milanac');
    // Sotto la barra la card della stanza aperta, con chi c'è dentro.
    expect(find.text(_cardMilan), findsOneWidget);
    expect(find.text('Marco e Luca sono dentro'), findsOneWidget);

    await tester.tap(find.text('Entra'));
    await tester.pumpAndSettle();
    // La stanza a schermo intero: Marco (sta parlando), Luca (in muto) e io.
    final room = find.byType(VoiceRoomPage);
    Finder inRoom(Finder f) => find.descendant(of: room, matching: f);
    expect(room, findsOneWidget);
    expect(inRoom(find.text('#MILAN AC')), findsOneWidget);
    expect(inRoom(find.text('Stanza vocale · 0:00')), findsOneWidget);
    expect(inRoom(find.text('Marco')), findsOneWidget);
    expect(inRoom(find.text('Sta parlando')), findsOneWidget);
    expect(inRoom(find.text('Luca')), findsOneWidget);
    expect(inRoom(find.text('Microfono spento')), findsOneWidget);
    expect(inRoom(find.text('Tu')), findsOneWidget);
    expect(inRoom(find.text('In ascolto')), findsOneWidget);
    expect(
      inRoom(find.textContaining('Aperta da Marco Rossi')),
      findsOneWidget,
    );
    final call = container.read(voiceCallProvider);
    expect(call.phase, VoicePhase.inRoom);
    expect(call.speaking, {agoraUidFor('p2')});
    final mutedIcons = inRoom(find.byIcon(Icons.mic_off_rounded));
    expect(mutedIcons, findsOneWidget);

    // Microfono spento: lo vedo su di me e sul pulsante.
    await tester.tap(find.text('Microfono'));
    await tester.pumpAndSettle();
    expect(container.read(voiceCallProvider).muted, isTrue);
    expect(inRoom(find.text('Microfono spento')), findsNWidgets(2));
    expect(mutedIcons, findsNWidgets(3));

    // Riduci: si torna alla chat con la chiamata ridotta a striscia.
    await tester.tap(
      find.byTooltip('Riduci la stanza a una striscia e torna alla chat'),
    );
    await tester.pumpAndSettle();
    expect(room, findsNothing);
    expect(find.text('Sei nella stanza vocale'), findsOneWidget);
    expect(find.text('#Milan AC · 0:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Riattiva il microfono'));
    await tester.pumpAndSettle();
    expect(container.read(voiceCallProvider).muted, isFalse);

    // Un tocco sulla striscia riapre la stanza; Esci la chiude e torna alla chat.
    await tester.tap(find.text('Sei nella stanza vocale'));
    await tester.pumpAndSettle();
    expect(room, findsOneWidget);
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(room, findsNothing);
    expect(container.read(voiceCallProvider).phase, VoicePhase.idle);
    expect(find.text(_cardMilan), findsOneWidget);

    // Generale: nessuna stanza. La apro io dalla barra in alto, esco e si chiude.
    await goToPath(tester, '/chat/main');
    expect(find.textContaining('Stanza vocale aperta'), findsNothing);
    await tester.tap(find.byTooltip('Stanza vocale'));
    await tester.pumpAndSettle();
    expect(inRoom(find.textContaining('Nessuno è in stanza')), findsOneWidget);
    await tester.tap(find.text('Apri la stanza'));
    await tester.pumpAndSettle();
    expect(inRoom(find.text('Tu')), findsOneWidget);
    expect(inRoom(find.textContaining('Aperta da te')), findsOneWidget);
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(room, findsNothing);
    expect(find.text('Sei nella stanza vocale'), findsNothing);
    expect(find.textContaining('Stanza vocale aperta'), findsNothing);
  });

  testWidgets('Tema chiaro: card, pulsante, stanza e striscia senza errori', (
    tester,
  ) async {
    final container = await startAppAt(tester, todayAt(17));
    await container.read(appearanceProvider.notifier).set(Appearance.chiaro);
    await tester.pumpAndSettle();
    await goToPath(tester, '/chat/milanac');
    expect(
      Theme.of(tester.element(find.text('Marco e Luca sono dentro')))
          .brightness,
      Brightness.light,
    );
    expect(find.byTooltip('Stanza vocale'), findsOneWidget);

    await tester.tap(find.text('Entra'));
    await tester.pumpAndSettle();
    // La stanza resta scura come nella tavola.
    expect(
      Theme.of(tester.element(find.text('Sta parlando'))).brightness,
      Brightness.dark,
    );
    await tester.tap(
      find.byTooltip('Riduci la stanza a una striscia e torna alla chat'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sei nella stanza vocale'), findsOneWidget);
    await tester.tap(find.byTooltip('Spegni il microfono'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Esci dalla stanza'));
    await tester.pumpAndSettle();
    expect(find.text('Sei nella stanza vocale'), findsNothing);
    expect(find.text(_cardMilan), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esci mentre entra: niente sessione, motore o segni di vita '
      'lasciati aperti', (tester) async {
    final c = _Call();
    final slow = c.slowJoin = Completer<void>();
    unawaited(c.notifier.enter(_generale));
    await tester.pump();
    expect(c.state.phase, VoicePhase.connecting);
    expect(c.focus, {AudioUse.chiamata});
    final engine = c.engines.single;
    expect(c.repo.mine, hasLength(1), reason: 'aprendo la stanza si è dentro');

    await c.notifier.leave();
    expect(c.state.phase, VoicePhase.idle);
    expect(engine.disposed, isTrue);
    expect(c.repo.mine, isEmpty);
    expect(c.focus, isEmpty);

    // La join che finisce tardi non riporta dentro nessuno.
    slow.complete();
    await tester.pump(const Duration(minutes: 3));
    expect(c.state.phase, VoicePhase.idle);
    expect(engine.joined, isFalse);
    expect(c.repo.beats, 0);
    // L'avviso fisso parte al tocco di "Entra" (con l'app in primo piano) e si
    // ferma uscendo; la join finita tardi non lo riaccende.
    expect(c.foreground.calls, ['start #Generale', 'stop']);
    c.container.dispose();
  });

  testWidgets('Esci mentre il server registra l\'ingresso: la sessione si '
      'chiude appena arriva', (tester) async {
    final c = _Call();
    final slow = c.repo.slowJoin = Completer<void>();
    unawaited(c.notifier.enter(_generale));
    await tester.pump();
    final leaving = c.notifier.leave();
    expect(c.state.phase, VoicePhase.idle);
    slow.complete();
    await leaving;
    expect(c.repo.mine, isEmpty);
    expect(c.engines, isEmpty);
    c.container.dispose();
  });

  testWidgets('Microfono e vivavoce toccati mentre entra arrivano al motore '
      'dopo la join', (tester) async {
    final c = _Call();
    final slow = c.slowJoin = Completer<void>();
    unawaited(c.notifier.enter(_generale));
    await tester.pump();
    await c.notifier.toggleMute();
    await c.notifier.toggleSpeakerphone();
    final engine = c.engines.single;
    expect(c.state.muted, isTrue);
    expect(c.state.speakerphone, isFalse);
    expect(engine.muted, isFalse, reason: 'il motore non è ancora dentro');

    slow.complete();
    await tester.pump();
    expect(c.state.phase, VoicePhase.inRoom);
    expect(engine.muted, isTrue);
    expect(engine.speakerphone, isFalse);
    expect(c.repo.mine.single.muted, isTrue, reason: 'gli altri lo vedono');
    expect(c.foreground.calls, ['start #Generale']);

    // Da dentro i comandi arrivano subito.
    await c.notifier.toggleMute();
    expect(engine.muted, isFalse);
    expect(c.repo.mine.single.muted, isFalse);

    await c.notifier.leave();
    expect(engine.disposed, isTrue);
    expect(c.foreground.calls, ['start #Generale', 'stop']);
    c.container.dispose();
  });

  testWidgets('Cambio stanza mentre entra: la prima si chiude, resta solo la '
      'seconda', (tester) async {
    final c = _Call();
    final slow = c.slowJoin = Completer<void>();
    unawaited(c.notifier.enter(_generale));
    await tester.pump();
    final first = c.engines.single;

    await c.notifier.enter(_tattiche);
    expect(first.disposed, isTrue);
    final second = c.engines.last;
    expect(c.engines, hasLength(2));
    expect(second.joined, isTrue);
    expect(c.state.phase, VoicePhase.inRoom);
    expect(c.state.channel?.id, _tattiche.id);
    expect(c.repo.mine.map((s) => s.roomId), [c.state.roomId]);

    // La join di Generale che finisce tardi non cambia niente.
    slow.complete();
    await tester.pump();
    expect(c.state.channel?.id, _tattiche.id);
    expect(c.repo.mine, hasLength(1));

    // Un solo segno di vita al minuto: quello di Tattiche.
    await tester.pump(const Duration(minutes: 1));
    expect(c.repo.beats, 1);

    await c.notifier.leave();
    expect(second.disposed, isTrue);
    expect(c.repo.mine, isEmpty);
    c.container.dispose();
  });

  testWidgets('Sessione chiusa dal server: al segno di vita la chiamata '
      'finisce con il motivo e libera tutto', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    final engine = c.engines.single;
    expect(c.state.phase, VoicePhase.inRoom);
    expect(engine.joined, isTrue);
    expect(engine.speakerphone, isTrue);
    expect(c.foreground.running, isTrue);
    expect(c.focus, {AudioUse.chiamata});

    // Il server chiude la sessione (3 minuti senza segnale).
    await c.repo.leave(c.state.sessionId!);
    await tester.pump(const Duration(minutes: 1));
    expect(c.state.phase, VoicePhase.error);
    expect(c.state.error, voiceLeftMessage);
    expect(c.state.channel?.id, _generale.id, reason: 'il foglio dà Riprova');
    expect(engine.disposed, isTrue);
    expect(c.foreground.running, isFalse);
    expect(c.focus, isEmpty);
    await tester.pump(const Duration(minutes: 3));
    expect(c.repo.beats, 1, reason: 'nessun altro segno di vita');
    c.container.dispose();
  });

  testWidgets('Ritorno nell\'app: subito un segno di vita, e se il server ha '
      'chiuso la sessione la chiamata finisce', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await c.repo.leave(c.state.sessionId!);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.repo.beats, 1);
    expect(c.state.phase, VoicePhase.error);
    expect(c.state.error, voiceLeftMessage);
    expect(c.engines.single.disposed, isTrue);
    c.container.dispose();
  });

  testWidgets('Rete assente per 3 minuti: la chiamata finisce', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    c.repo.offline = true;
    await tester.pump(const Duration(minutes: 2));
    expect(c.state.phase, VoicePhase.inRoom, reason: 'due minuti si reggono');
    await tester.pump(const Duration(minutes: 1));
    expect(c.state.phase, VoicePhase.error);
    expect(c.state.error, startsWith('Connessione persa'));
    expect(c.engines.single.disposed, isTrue);
    c.container.dispose();
  });

  testWidgets('Connessione persa dopo l\'ingresso: errore, sessione chiusa e '
      'motore liberato', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    final engine = c.engines.single;
    engine.fail(
      'Connessione con la stanza persa: controlla la rete e rientra.',
    );
    await tester.pump();
    expect(c.state.phase, VoicePhase.error);
    expect(c.state.error, startsWith('Connessione con la stanza persa'));
    expect(engine.disposed, isTrue);
    expect(c.repo.mine, isEmpty);
    expect(c.foreground.running, isFalse);
    c.container.dispose();
  });

  testWidgets('Mentre si registra il microfono della stanza è in muto, poi '
      'torna come prima', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    final engine = c.engines.single;
    final focus = c.container.read(audioFocusProvider.notifier);

    focus.claim(AudioUse.registrazioneVocale);
    await tester.pump();
    expect(engine.muted, isTrue);
    expect(c.state.muted, isFalse, reason: 'il pulsante mostra la scelta');
    expect(c.state.phase, VoicePhase.inRoom, reason: 'la stanza resta');
    focus.release(AudioUse.registrazioneVocale);
    await tester.pump();
    expect(engine.muted, isFalse);

    // Con il muto scelto dall'utente, dopo la registrazione resta in muto.
    await c.notifier.toggleMute();
    focus.claim(AudioUse.registrazioneReplay);
    await tester.pump();
    focus.release(AudioUse.registrazioneReplay);
    await tester.pump();
    expect(engine.muted, isTrue);
    expect(c.focus, {AudioUse.chiamata});

    await c.notifier.leave();
    expect(c.focus, isEmpty);
    c.container.dispose();
  });

  testWidgets('Logout: prima esce dalla stanza e ferma l\'audio', (
    tester,
  ) async {
    final c = _Call();
    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c.container,
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    await c.notifier.enter(_generale);
    c.container.read(audioFocusProvider.notifier).claim(AudioUse.vocale);
    expect(c.focus, {AudioUse.vocale, AudioUse.chiamata});

    await logout(ref);
    expect(c.state.phase, VoicePhase.idle);
    expect(c.engines.single.disposed, isTrue);
    expect(c.repo.mine, isEmpty);
    expect(c.foreground.running, isFalse);
    expect(c.focus, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.container.dispose();
  });

  testWidgets('Esci: la stanza si chiude subito, anche se il server non '
      'risponde', (tester) async {
    final repo = _TestRepo();
    final container = await startAppAt(
      tester,
      todayAt(17),
      overrides: [voiceRepositoryProvider.overrideWithValue(repo)],
    );
    await goToPath(tester, '/chat/milanac');
    await tester.tap(find.text('Entra'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceRoomPage), findsOneWidget);
    expect(repo.mine, hasLength(1));

    final server = repo.slowLeave = Completer<void>();
    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceRoomPage), findsNothing);
    expect(container.read(voiceCallProvider).phase, VoicePhase.idle);
    expect(find.text('Sei nella stanza vocale'), findsNothing);
    // L'uscita sul server arriva dopo, da sola.
    server.complete();
    await tester.pumpAndSettle();
    expect(repo.mine, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Avviso fisso rifiutato da Android dentro il servizio: al ritorno '
    'nell\'app si riavvia',
    (tester) async {
      final c = _Call();
      await c.notifier.enter(_generale);
      expect(c.foreground.calls, ['start #Generale']);

      // L'avvio era stato accettato, poi Android l'ha rifiutato (Android 14).
      c.foreground.refused = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(c.foreground.calls, ['start #Generale', 'start #Generale']);

      // Attivo: al ritorno dopo non si riavvia.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(c.foreground.calls, hasLength(2));
      await c.notifier.leave();
      expect(c.foreground.calls.last, 'stop');
      c.container.dispose();
    },
  );

  testWidgets('Permesso Bluetooth: si chiede prima di entrare; uscendo con il '
      'dialogo aperto non si entra', (tester) async {
    final c = _Call();
    final dialog = c.foreground.bluetoothDialog = Completer<void>();
    unawaited(c.notifier.enter(_generale));
    await tester.pump();
    expect(c.foreground.bluetoothAsks, 1);
    expect(c.state.phase, VoicePhase.connecting);
    expect(c.repo.mine, isEmpty, reason: 'si entra dopo la risposta');
    expect(c.engines, isEmpty);
    dialog.complete();
    await tester.pump();
    expect(c.state.phase, VoicePhase.inRoom);
    expect(c.engines.single.joined, isTrue);
    await c.notifier.leave();

    final again = c.foreground.bluetoothDialog = Completer<void>();
    unawaited(c.notifier.enter(_generale));
    await tester.pump();
    final leaving = c.notifier.leave();
    expect(c.state.phase, VoicePhase.idle);
    again.complete();
    await leaving;
    await tester.pump();
    expect(c.state.phase, VoicePhase.idle);
    expect(c.repo.mine, isEmpty);
    expect(c.engines, hasLength(1), reason: 'nessun motore nuovo');
    c.container.dispose();
  });

  testWidgets(
    'Permesso Bluetooth su Android: si aspetta la risposta al dialogo '
    '(il ritorno nell\'app), e solo se il dialogo compare',
    (tester) async {
      const channel = MethodChannel('milanac/stanza_vocale');
      final messenger = tester.binding.defaultBinaryMessenger;
      var dialog = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'bluetooth');
        return dialog;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var answered = false;
      void ask() => unawaited(
        const AndroidVoiceForeground().askBluetooth().then(
          (_) => answered = true,
        ),
      );

      // Il dialogo mette l'app in pausa: si aspetta finché non torna.
      ask();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 10));
      expect(answered, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(answered, isTrue);

      // Il dialogo non compare (permesso negato per sempre): un attimo e via.
      answered = false;
      ask();
      await tester.pump(const Duration(seconds: 1));
      expect(answered, isTrue);

      // Permesso già dato o niente auricolari: nessuna attesa.
      dialog = false;
      answered = false;
      ask();
      await tester.pump();
      expect(answered, isTrue);
    },
  );

  group('Rinnovo del biglietto della stanza', () {
    final start = DateTime(2026, 10, 12, 21);

    test(
      'senza rete riprova (2, 4 secondi...) finché vale, poi riesce',
      () async {
        var now = start;
        final waits = <Duration>[];
        final applied = <String>[];
        var attempts = 0;
        final problem = await renewVoiceTicket(
          refresh: () async {
            if (++attempts < 3) throw Exception('rete assente');
            return 'nuovo';
          },
          apply: (token) async => applied.add(token),
          stopped: () => false,
          until: start.add(const Duration(seconds: 30)),
          now: () => now,
          wait: (d) async {
            waits.add(d);
            now = now.add(d);
          },
        );
        expect(problem, isNull);
        expect(applied, ['nuovo']);
        expect(waits, const [Duration(seconds: 2), Duration(seconds: 4)]);
      },
    );

    test('se la rete non torna prima della scadenza, la chiamata finisce con '
        'il motivo', () async {
      var now = start;
      final until = start.add(const Duration(seconds: 30));
      var attempts = 0;
      final problem = await renewVoiceTicket(
        refresh: () async {
          attempts++;
          throw Exception('rete assente');
        },
        apply: (_) async => fail('nessun biglietto'),
        stopped: () => false,
        until: until,
        now: () => now,
        wait: (d) async => now = now.add(d),
      );
      expect(
        problem?.message,
        startsWith('Biglietto della stanza non rinnovato'),
      );
      expect(attempts, 6);
      expect(now.isAfter(until), isFalse, reason: 'non oltre la scadenza');
    });

    test('una richiesta bloccata non consuma tutto il tempo: dopo il tempo '
        'massimo si riprova', () async {
      var attempts = 0;
      final problem = await renewVoiceTicket(
        refresh: () {
          // La prima richiesta non risponde mai, la seconda sì.
          if (++attempts == 1) return Completer<String>().future;
          return Future.value('nuovo');
        },
        apply: (_) async {},
        stopped: () => false,
        until: start.add(const Duration(seconds: 30)),
        now: () => start,
        wait: (_) async {},
        attemptTimeout: const Duration(milliseconds: 20),
      );
      expect(problem, isNull);
      expect(attempts, 2);
    });

    test('una risposta definitiva del server non si riprova; uscendo intanto '
        'non si riprova più', () async {
      var attempts = 0;
      var problem = await renewVoiceTicket(
        refresh: () async {
          attempts++;
          throw const VoiceException(voiceLeftMessage);
        },
        apply: (_) async {},
        stopped: () => false,
        until: start.add(const Duration(seconds: 30)),
        now: () => start,
        wait: (_) async => fail('nessuna attesa'),
      );
      expect(problem?.message, voiceLeftMessage);
      expect(attempts, 1);

      var left = false;
      attempts = 0;
      problem = await renewVoiceTicket(
        refresh: () async {
          attempts++;
          throw Exception('rete assente');
        },
        apply: (_) async {},
        stopped: () => left,
        until: start.add(const Duration(seconds: 30)),
        now: () => start,
        wait: (_) async => left = true,
      );
      expect(problem, isNull);
      expect(attempts, 1);
    });
  });

  testWidgets('Filtro rumore: forte di serie, cambia subito nel motore e resta '
      'per la volta dopo', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    final first = c.engines.single;
    expect(c.state.noiseFilter, NoiseFilter.forte);
    expect(first.noiseFilter, NoiseFilter.forte);

    await c.notifier.setNoiseFilter(NoiseFilter.normale);
    expect(c.state.noiseFilter, NoiseFilter.normale);
    expect(first.noiseFilter, NoiseFilter.normale);

    // Il motore nuovo parte già con la scelta salvata sul telefono.
    await c.notifier.leave();
    await c.notifier.enter(_tattiche);
    final second = c.engines.last;
    expect(second, isNot(same(first)));
    expect(second.noiseFilter, NoiseFilter.normale);
    expect(c.state.noiseFilter, NoiseFilter.normale);
    await c.notifier.leave();
    c.container.dispose();
  });

  testWidgets('Rete che cade e torna, uscita dell\'audio e rete debole '
      'arrivano alla chiamata; uscendo non resta niente', (tester) async {
    final c = _Call();
    await c.notifier.enter(_generale);
    final engine = c.engines.single;

    engine.reconnect(true);
    await tester.pump();
    expect(c.state.reconnecting, isTrue);
    engine.reconnect(false);
    await tester.pump();
    expect(c.state.reconnecting, isFalse);

    engine
      ..routeTo(VoiceRoute.cuffie)
      ..weak({agoraUidFor('demo')});
    await tester.pump();
    expect(c.state.route, VoiceRoute.cuffie);
    expect(c.state.weak, {agoraUidFor('demo')});

    engine.reconnect(true);
    await tester.pump();
    await c.notifier.leave();
    expect(c.state.reconnecting, isFalse);
    expect(c.state.route, isNull);
    expect(c.state.weak, isEmpty);
    // Il motore chiuso non cambia più niente.
    engine.reconnect(true);
    await tester.pump();
    expect(c.state.reconnecting, isFalse);
    c.container.dispose();
  });

  testWidgets('Stanza: filtro rumore, avviso di rete instabile (anche nella '
      'striscia), consiglio sul vivavoce e rete debole', (tester) async {
    final engines = <DemoVoiceEngine>[];
    final container = await startAppAt(
      tester,
      todayAt(17),
      overrides: [
        voiceEngineFactoryProvider.overrideWithValue(() {
          final engine = DemoVoiceEngine(speakingUid: agoraUidFor('p2'));
          engines.add(engine);
          return engine;
        }),
      ],
    );
    await goToPath(tester, '/chat/milanac');
    await tester.tap(find.text('Entra'));
    await tester.pumpAndSettle();
    final room = find.byType(VoiceRoomPage);
    Finder inRoom(Finder f) => find.descendant(of: room, matching: f);
    final engine = engines.single;

    // Filtro rumore: forte di serie; "Normale" vale subito.
    expect(inRoom(find.text('Filtro rumore')), findsOneWidget);
    expect(inRoom(find.textContaining('Toglie la TV')), findsOneWidget);
    await tester.ensureVisible(inRoom(find.text('Normale')));
    await tester.pumpAndSettle();
    await tester.tap(inRoom(find.text('Normale')));
    await tester.pumpAndSettle();
    expect(container.read(voiceCallProvider).noiseFilter, NoiseFilter.normale);
    expect(engine.noiseFilter, NoiseFilter.normale);
    expect(inRoom(find.textContaining('Voce più naturale')), findsOneWidget);

    // Vivavoce con altri dentro: il consiglio sugli auricolari; con le cuffie no.
    final tip = inRoom(find.textContaining('Sei in vivavoce'));
    expect(tip, findsNothing);
    engine.routeTo(VoiceRoute.vivavoce);
    await tester.pumpAndSettle();
    expect(tip, findsOneWidget);
    engine.routeTo(VoiceRoute.cuffie);
    await tester.pumpAndSettle();
    expect(tip, findsNothing);

    // Rete debole di Luca (in muto): lo dice al posto di "Microfono spento".
    engine.weak({agoraUidFor('p3')});
    await tester.pumpAndSettle();
    expect(inRoom(find.text('Rete debole')), findsOneWidget);
    expect(inRoom(find.byIcon(Icons.signal_wifi_bad_rounded)), findsOneWidget);
    engine.weak({});
    await tester.pumpAndSettle();
    expect(inRoom(find.text('Rete debole')), findsNothing);

    // Rete che cade: l'avviso nella stanza e nella striscia; poi torna il tempo.
    // La rotellina gira sempre: niente pumpAndSettle finché si vede (l'avviso del
    // motore arriva dopo il disegno: lo mostra il fotogramma dopo).
    engine.reconnect(true);
    await tester.pump();
    await tester.pump();
    expect(inRoom(find.textContaining('mi sto ricollegando')), findsOneWidget);
    await tester.tap(
      find.byTooltip('Riduci la stanza a una striscia e torna alla chat'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rete instabile: mi ricollego…'), findsOneWidget);
    engine.reconnect(false);
    await tester.pumpAndSettle();
    expect(find.text('Rete instabile: mi ricollego…'), findsNothing);
    expect(find.text('#Milan AC · 0:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Esci dalla stanza'));
    await tester.pumpAndSettle();
    expect(engine.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Stanze aperte: con un altro account si ricaricano, senza account '
      'nessuna', () async {
    final repo = _TestRepo();
    final container = ProviderContainer(
      overrides: [
        voiceRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(_accountProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(openVoiceRoomsProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await container.read(openVoiceRoomsProvider.future), hasLength(1));
    expect(repo.roomStreams, 1);

    container.read(_accountProvider.notifier).set(null);
    expect(await container.read(openVoiceRoomsProvider.future), isEmpty);

    container.read(_accountProvider.notifier).set('p2');
    expect(await container.read(openVoiceRoomsProvider.future), hasLength(1));
    expect(repo.roomStreams, 2);
  });
}
