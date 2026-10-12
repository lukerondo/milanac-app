import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milanac/core/appearance.dart';
import 'package:milanac/core/audio_focus.dart';
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

/// Stanze demo che contano i segni di vita, possono restare senza rete e tenere
/// in sospeso l'ingresso sul server.
class _TestRepo extends DemoVoiceRepository {
  var beats = 0;
  var offline = false;
  Completer<void>? slowJoin;

  /// Le proprie sessioni aperte.
  List<VoiceSession> get mine =>
      sessions.where((s) => s.userId == 'demo' && s.isActive).toList();

  @override
  Future<String> join(String roomId, int agoraUid) async {
    final wait = slowJoin?.future;
    if (wait != null) await wait;
    return super.join(roomId, agoraUid);
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

  bool get running => calls.isNotEmpty && calls.last != 'stop';

  @override
  Future<bool> start(String channelName) async {
    calls.add('start #$channelName');
    return true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }
}

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
    expect(inRoom(find.textContaining('Aperta da Marco Rossi')), findsOneWidget);
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
      Theme.of(tester.element(find.text('Marco e Luca sono dentro'))).brightness,
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
    expect(c.foreground.calls, isEmpty);
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
    engine.fail('Connessione con la stanza persa: controlla la rete e rientra.');
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
}
