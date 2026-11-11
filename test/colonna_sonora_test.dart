import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/audio_focus.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/musica/club_track.dart';
import 'package:milanac/features/musica/soundtrack.dart';

const _club = '/telefono/colonna_sonora_club_100.mp3';

/// Lettore finto: i file in [broken] non si possono aprire (formato non supportato)
/// e, come just_audio, dopo un caricamento fallito non ha più niente da suonare.
/// Con [blocked] il play non parte, come nel browser prima di un tocco.
class _Engine implements SoundtrackEngine {
  final broken = <String>{};
  String? loaded;
  var playing = false;
  var blocked = false;
  Duration? seekedTo;

  @override
  void Function()? onPlayFailed;

  @override
  Future<void> load(String path) async {
    if (broken.contains(path)) {
      loaded = null;
      throw Exception('formato non supportato');
    }
    loaded = path;
  }

  @override
  Future<void> play() async {
    if (blocked) {
      scheduleMicrotask(() => onPlayFailed?.call());
      return;
    }
    playing = loaded != null;
  }

  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> stop() async => playing = false;
  @override
  Future<void> seek(Duration position) async => seekedTo = position;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => null;
  @override
  Future<void> dispose() async {}
}

/// Archivio finto: la colonna sonora del club si scarica quando il test completa
/// [download] (o subito, se [instantClub]).
class _Store extends MemorySoundtrackStore {
  /// Prima apertura dopo l'installazione: nessuna scelta salvata.
  _Store() {
    values.clear();
  }

  var next = ('/telefono/fifa.mp3', 'fifa.mp3');
  final deleted = <String>[];
  var instantClub = true;
  var clubRequests = 0;
  Completer<String>? download;
  void Function(double)? progress;

  @override
  Future<(String, String)?> importTrack() async => next;
  @override
  Future<void> deleteTrack(String path) async => deleted.add(path);
  @override
  Future<String> clubTrack({void Function(double progress)? onProgress}) {
    clubRequests++;
    if (instantClub) return Future.value(_club);
    progress = onProgress;
    return (download = Completer<String>()).future;
  }
}

ProviderContainer _container(_Engine engine, _Store store) {
  final c = ProviderContainer(
    overrides: [
      soundtrackEngineProvider.overrideWithValue(engine),
      soundtrackStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  c.read(introDoneProvider.notifier).complete();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'colonna sonora: un file che il telefono non legge non resta "in '
    'riproduzione" senza audio; vocali e chiamate la mettono in pausa',
    () async {
      final engine = _Engine();
      final store = _Store();
      final c = _container(engine, store);
      final ctrl = c.read(soundtrackProvider.notifier);
      await pumpEventQueue();
      await ctrl.pickTrack();
      await pumpEventQueue();
      expect(engine.loaded, '/telefono/fifa.mp3');
      expect(engine.playing, isTrue);
      expect(c.read(soundtrackProvider).playing, isTrue);

      // Un .ogg su iPhone: errore, la copia si cancella e torna la musica di prima.
      store.next = ('/telefono/canzone.ogg', 'canzone.ogg');
      engine.broken.add('/telefono/canzone.ogg');
      await expectLater(ctrl.pickTrack(), throwsException);
      await pumpEventQueue();
      // La colonna sonora del club, sostituita dal primo file, resta sul telefono.
      expect(store.deleted, ['/telefono/canzone.ogg']);
      expect(engine.loaded, '/telefono/fifa.mp3');
      expect(c.read(soundtrackProvider).trackName, 'fifa.mp3');
      expect(c.read(soundtrackProvider).playing, isTrue);
      expect(engine.playing, isTrue);

      // Un vocale prende l'audio: la musica aspetta, poi riprende da sola.
      final focus = c.read(audioFocusProvider.notifier);
      focus.claim(AudioUse.vocale);
      await pumpEventQueue();
      expect(engine.playing, isFalse);
      expect(c.read(soundtrackProvider).playing, isFalse);
      focus.release(AudioUse.vocale);
      await pumpEventQueue();
      expect(engine.playing, isTrue);

      // In muto resta ferma anche quando l'audio torna libero.
      await ctrl.toggleMute();
      focus.claim(AudioUse.chiamata);
      await pumpEventQueue();
      focus.release(AudioUse.chiamata);
      await pumpEventQueue();
      expect(engine.playing, isFalse);
      expect(c.read(soundtrackProvider).playing, isFalse);
    },
  );

  test('colonna sonora: con la musica tolta, un primo file non leggibile non '
      'lascia una musica fantasma', () async {
    final engine = _Engine()..broken.add('/telefono/fifa.mp3');
    final store = _Store()..values['source'] = 'none';
    final c = _container(engine, store);
    final ctrl = c.read(soundtrackProvider.notifier);
    await pumpEventQueue();
    expect(store.clubRequests, 0);
    await expectLater(ctrl.pickTrack(), throwsException);
    await pumpEventQueue();
    final s = c.read(soundtrackProvider);
    expect(s.hasTrack, isFalse);
    expect(s.playing, isFalse);
    expect(s.busy, isFalse);
    expect(s.source, SoundtrackSource.none);
    expect(store.deleted, ['/telefono/fifa.mp3']);
    expect(store.values['path'], isNull);
    expect(store.clubRequests, 0);
  });

  test('colonna sonora del club: alla prima apertura si scarica (con '
      "l'avanzamento) e parte da sola dopo l'intro", () async {
    final engine = _Engine();
    final store = _Store()..instantClub = false;
    final c = _container(engine, store);
    c.read(soundtrackProvider.notifier);
    await pumpEventQueue();

    var s = c.read(soundtrackProvider);
    expect(s.source, SoundtrackSource.club);
    expect(s.hasTrack, isFalse);
    expect(store.clubRequests, 1);
    store.progress!(.42);
    s = c.read(soundtrackProvider);
    expect(s.download, .42);
    expect(s.playing, isFalse);

    store.download!.complete(_club);
    await pumpEventQueue();
    s = c.read(soundtrackProvider);
    expect(s.download, isNull);
    expect(s.trackName, ClubTrack.title);
    expect(s.playing, isTrue);
    expect(engine.loaded, _club);
    expect(engine.playing, isTrue);
  });

  test('colonna sonora del club: senza rete si riprova, e riprende dal punto '
      'in cui era rimasta', () async {
    final engine = _Engine();
    final store = _Store()
      ..instantClub = false
      ..values['ms'] = 61000;
    final c = _container(engine, store);
    final ctrl = c.read(soundtrackProvider.notifier);
    await pumpEventQueue();
    store.download!.completeError(Exception('niente rete'));
    await pumpEventQueue();
    var s = c.read(soundtrackProvider);
    expect(s.downloadFailed, isTrue);
    expect(s.hasTrack, isFalse);
    expect(engine.playing, isFalse);
    // Il pulsante muto non fa niente finché non c'è musica.
    expect(await ctrl.toggleMute(), isFalse);

    final retry = ctrl.retryClubTrack();
    expect(c.read(soundtrackProvider).downloadFailed, isFalse);
    store.download!.complete(_club);
    await retry;
    await pumpEventQueue();
    s = c.read(soundtrackProvider);
    expect(s.trackName, ClubTrack.title);
    expect(engine.seekedTo, const Duration(seconds: 61));
    expect(engine.playing, isTrue);
  });

  test('colonna sonora: chi aveva già scelto un file lo ritrova; si torna al '
      'club, si toglie la musica e la scelta resta alla riapertura', () async {
    final engine = _Engine();
    final store = _Store()
      ..values.addAll({'path': '/telefono/vecchio.mp3', 'name': 'vecchio.mp3'});
    var c = _container(engine, store);
    var ctrl = c.read(soundtrackProvider.notifier);
    await pumpEventQueue();
    var s = c.read(soundtrackProvider);
    expect(s.source, SoundtrackSource.file);
    expect(s.trackName, 'vecchio.mp3');
    expect(engine.loaded, '/telefono/vecchio.mp3');
    expect(store.clubRequests, 0);

    // Torna alla colonna sonora del club: la copia del vecchio file si cancella.
    await ctrl.useClubTrack();
    await pumpEventQueue();
    s = c.read(soundtrackProvider);
    expect(s.source, SoundtrackSource.club);
    expect(s.trackName, ClubTrack.title);
    expect(engine.loaded, _club);
    expect(engine.playing, isTrue);
    expect(store.deleted, ['/telefono/vecchio.mp3']);
    expect(store.values['source'], 'club');
    expect(store.values['path'], isNull);

    // Musica tolta: niente club neanche alla prossima apertura.
    await ctrl.removeTrack();
    await pumpEventQueue();
    s = c.read(soundtrackProvider);
    expect(s.source, SoundtrackSource.none);
    expect(s.hasTrack, isFalse);
    expect(engine.playing, isFalse);
    expect(store.deleted, ['/telefono/vecchio.mp3']);
    c.dispose();

    final requests = store.clubRequests;
    c = _container(engine, store);
    ctrl = c.read(soundtrackProvider.notifier);
    await pumpEventQueue();
    expect(c.read(soundtrackProvider).source, SoundtrackSource.none);
    expect(store.clubRequests, requests);

    // E si rimette con un tocco.
    await ctrl.useClubTrack();
    await pumpEventQueue();
    expect(c.read(soundtrackProvider).trackName, ClubTrack.title);
    expect(engine.playing, isTrue);
  });

  test(
    'colonna sonora: se il file scelto è sparito torna quella del club',
    () async {
      final engine = _Engine()..broken.add('/telefono/sparito.mp3');
      final store = _Store()
        ..values.addAll({
          'source': 'file',
          'path': '/telefono/sparito.mp3',
          'name': 'sparito.mp3',
        });
      final c = _container(engine, store);
      c.read(soundtrackProvider.notifier);
      await pumpEventQueue();
      final s = c.read(soundtrackProvider);
      expect(s.source, SoundtrackSource.club);
      expect(s.trackName, ClubTrack.title);
      expect(engine.playing, isTrue);
      expect(store.values['source'], 'club');
    },
  );

  test('colonna sonora: se il browser blocca la musica, riparte al primo '
      'tocco', () async {
    final engine = _Engine()..blocked = true;
    final store = _Store();
    final c = _container(engine, store);
    c.read(soundtrackProvider.notifier);
    await pumpEventQueue();
    expect(c.read(soundtrackProvider).hasTrack, isTrue);
    expect(c.read(soundtrackProvider).playing, isFalse);
    expect(engine.playing, isFalse);

    engine.blocked = false;
    final router = GestureBinding.instance.pointerRouter;
    router.route(const PointerDownEvent(pointer: 7));
    await pumpEventQueue();
    expect(engine.playing, isFalse);
    router.route(const PointerUpEvent(pointer: 7));
    await pumpEventQueue();
    expect(engine.playing, isTrue);
    expect(c.read(soundtrackProvider).playing, isTrue);
  });
}
