import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milanac/core/audio_focus.dart';
import 'package:milanac/features/intro/intro_state.dart';
import 'package:milanac/features/musica/soundtrack.dart';

/// Lettore finto: i file in [broken] non si possono aprire (formato non supportato)
/// e, come just_audio, dopo un caricamento fallito non ha più niente da suonare.
class _Engine implements SoundtrackEngine {
  final broken = <String>{};
  String? loaded;
  var playing = false;

  @override
  Future<void> load(String path) async {
    if (broken.contains(path)) {
      loaded = null;
      throw Exception('formato non supportato');
    }
    loaded = path;
  }

  @override
  Future<void> play() async => playing = loaded != null;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> stop() async => playing = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => null;
  @override
  Future<void> dispose() async {}
}

class _Store extends MemorySoundtrackStore {
  var next = ('/telefono/fifa.mp3', 'fifa.mp3');
  final deleted = <String>[];

  @override
  Future<(String, String)?> importTrack() async => next;
  @override
  Future<void> deleteTrack(String path) async => deleted.add(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'colonna sonora: un file che il telefono non legge non resta "in '
    'riproduzione" senza audio; vocali e chiamate la mettono in pausa',
    () async {
      final engine = _Engine();
      final store = _Store();
      final c = ProviderContainer(
        overrides: [
          soundtrackEngineProvider.overrideWithValue(engine),
          soundtrackStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      c.read(introDoneProvider.notifier).complete();
      final ctrl = c.read(soundtrackProvider.notifier);
      await pumpEventQueue();
      await ctrl.pickTrack();
      await pumpEventQueue();
      expect(engine.playing, isTrue);
      expect(c.read(soundtrackProvider).playing, isTrue);

      // Un .ogg su iPhone: errore, la copia si cancella e torna la musica di prima.
      store.next = ('/telefono/canzone.ogg', 'canzone.ogg');
      engine.broken.add('/telefono/canzone.ogg');
      await expectLater(ctrl.pickTrack(), throwsException);
      await pumpEventQueue();
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

  test('colonna sonora: il primo file non leggibile non lascia una musica fantasma', () async {
    final engine = _Engine()..broken.add('/telefono/fifa.mp3');
    final store = _Store();
    final c = ProviderContainer(
      overrides: [
        soundtrackEngineProvider.overrideWithValue(engine),
        soundtrackStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    c.read(introDoneProvider.notifier).complete();
    final ctrl = c.read(soundtrackProvider.notifier);
    await pumpEventQueue();
    await expectLater(ctrl.pickTrack(), throwsException);
    await pumpEventQueue();
    final s = c.read(soundtrackProvider);
    expect(s.hasTrack, isFalse);
    expect(s.playing, isFalse);
    expect(s.busy, isFalse);
    expect(store.deleted, ['/telefono/fifa.mp3']);
    expect(store.values['path'], isNull);
  });
}
