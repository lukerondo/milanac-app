import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import '../intro/intro_state.dart';

/// Musica di sottofondo dell'app.
///
/// Ognuno sceglie un file audio dal proprio telefono (es. una compilation di canzoni
/// FIFA scaricata): l'app ne tiene una copia privata, lo riproduce in loop e lo mette
/// in pausa con il pulsante muto. Nessuna canzone è inclusa nell'app.
class SoundtrackState {
  const SoundtrackState({
    this.trackName,
    this.muted = false,
    this.playing = false,
    this.volume = .5,
    this.autoplay = true,
    this.busy = false,
  });

  /// Nome del file scelto (null = nessuna musica impostata).
  final String? trackName;
  final bool muted;
  final bool playing;
  final double volume;

  /// Riparte da sola all'apertura dell'app (se non è in muto).
  final bool autoplay;
  final bool busy;

  bool get hasTrack => trackName != null;

  SoundtrackState copyWith({
    String? trackName,
    bool clearTrack = false,
    bool? muted,
    bool? playing,
    double? volume,
    bool? autoplay,
    bool? busy,
  }) => SoundtrackState(
    trackName: clearTrack ? null : trackName ?? this.trackName,
    muted: muted ?? this.muted,
    playing: playing ?? this.playing,
    volume: volume ?? this.volume,
    autoplay: autoplay ?? this.autoplay,
    busy: busy ?? this.busy,
  );
}

/// Riproduttore: just_audio sul telefono, muto nei test e nella demo.
abstract class SoundtrackEngine {
  Future<void> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Duration get position;
  Future<void> dispose();
}

class JustAudioEngine implements SoundtrackEngine {
  final _player = AudioPlayer();

  @override
  Future<void> load(String path) async {
    await _player.setFilePath(path);
    await _player.setLoopMode(LoopMode.one);
  }

  // play() di just_audio termina solo quando la riproduzione si ferma: non va atteso.
  @override
  Future<void> play() async => unawaited(_player.play());
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Duration get position => _player.position;
  @override
  Future<void> dispose() => _player.dispose();
}

class SilentEngine implements SoundtrackEngine {
  @override
  Future<void> load(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Duration get position => Duration.zero;
  @override
  Future<void> dispose() async {}
}

/// Dove sta il file scelto e le preferenze (muto, volume, avvio automatico).
abstract class SoundtrackStore {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> values);

  /// Fa scegliere un file audio e ne salva una copia privata: (percorso, nome).
  Future<(String, String)?> importTrack();
  Future<void> deleteTrack(String path);
}

class DeviceSoundtrackStore implements SoundtrackStore {
  static const _prefix = 'soundtrack.';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<Map<String, Object?>> read() async {
    final all = await _prefs.getAll(
      allowList: {
        for (final k in ['path', 'name', 'muted', 'volume', 'autoplay', 'ms'])
          '$_prefix$k',
      },
    );
    return {
      for (final e in all.entries) e.key.substring(_prefix.length): e.value,
    };
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    for (final MapEntry(:key, :value) in values.entries) {
      final k = '$_prefix$key';
      switch (value) {
        case null:
          await _prefs.remove(k);
        case final String v:
          await _prefs.setString(k, v);
        case final bool v:
          await _prefs.setBool(k, v);
        case final int v:
          await _prefs.setInt(k, v);
        case final double v:
          await _prefs.setDouble(k, v);
      }
    }
  }

  @override
  Future<(String, String)?> importTrack() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Scegli la musica di sottofondo',
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'aac',
        'wav',
        'ogg',
        'opus',
        'flac',
      ],
    );
    if (picked == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final ext = picked.extension ?? 'mp3';
    // Nome nuovo a ogni scelta: il vecchio file viene cancellato dopo.
    final target = File(
      '${dir.path}/colonna_sonora_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    final sink = target.openWrite();
    await sink.addStream(picked.readAsByteStream());
    await sink.close();
    return (target.path, picked.name);
  }

  @override
  Future<void> deleteTrack(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// Versione in memoria per la demo e i test.
class MemorySoundtrackStore implements SoundtrackStore {
  final values = <String, Object?>{};

  @override
  Future<Map<String, Object?>> read() async => Map.of(values);
  @override
  Future<void> write(Map<String, Object?> v) async => values.addAll(v);
  @override
  Future<(String, String)?> importTrack() async =>
      ('/demo/fifa.mp3', 'Canzoni iconiche FIFA.mp3');
  @override
  Future<void> deleteTrack(String path) async {}
}

final soundtrackEngineProvider = Provider<SoundtrackEngine>((ref) {
  final engine = AppConfig.isDemo ? SilentEngine() : JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final soundtrackStoreProvider = Provider<SoundtrackStore>(
  (ref) => AppConfig.isDemo ? MemorySoundtrackStore() : DeviceSoundtrackStore(),
);

final soundtrackProvider =
    NotifierProvider<SoundtrackController, SoundtrackState>(
      SoundtrackController.new,
    );

class SoundtrackController extends Notifier<SoundtrackState> {
  String? _path;
  bool _inForeground = true;
  Timer? _savePosition;
  AppLifecycleListener? _lifecycle;

  SoundtrackEngine get _engine => ref.read(soundtrackEngineProvider);
  SoundtrackStore get _store => ref.read(soundtrackStoreProvider);

  @override
  SoundtrackState build() {
    // La musica parte solo dopo il video di benvenuto.
    ref.listen(introDoneProvider, (_, done) {
      if (done) _sync();
    });
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _inForeground = false;
        _sync();
      },
      onShow: () {
        _inForeground = true;
        _sync();
      },
    );
    ref.onDispose(() {
      _lifecycle?.dispose();
      _savePosition?.cancel();
    });
    Future.microtask(_restore);
    return const SoundtrackState(busy: true);
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.read();
      final path = saved['path'] as String?;
      final volume = (saved['volume'] as num?)?.toDouble() ?? .5;
      state = state.copyWith(
        volume: volume,
        autoplay: saved['autoplay'] as bool? ?? true,
        // All'apertura riparte solo con l'avvio automatico attivo.
        muted:
            (saved['muted'] as bool? ?? false) ||
            !(saved['autoplay'] as bool? ?? true),
      );
      if (path != null) {
        await _engine.load(path);
        await _engine.setVolume(volume);
        final ms = saved['ms'] as int?;
        if (ms != null) await _engine.seek(Duration(milliseconds: ms));
        _path = path;
        state = state.copyWith(trackName: saved['name'] as String? ?? 'Musica');
      }
    } catch (_) {
      // File sparito o non leggibile: si riparte senza musica.
      _path = null;
      state = state.copyWith(clearTrack: true);
    } finally {
      state = state.copyWith(busy: false);
      await _sync();
    }
  }

  /// Suona solo se c'è un file, non è in muto, l'app è in primo piano e l'intro è finita.
  Future<void> _sync() async {
    final shouldPlay =
        _path != null &&
        !state.muted &&
        _inForeground &&
        ref.read(introDoneProvider);
    if (shouldPlay == state.playing) return;
    if (shouldPlay) {
      await _engine.play();
      _savePosition ??= Timer.periodic(
        const Duration(seconds: 20),
        (_) => _rememberPosition(),
      );
    } else {
      await _engine.pause();
      _savePosition?.cancel();
      _savePosition = null;
      await _rememberPosition();
    }
    state = state.copyWith(playing: shouldPlay);
  }

  Future<void> _rememberPosition() =>
      _store.write({'ms': _engine.position.inMilliseconds});

  /// Pulsante muto. Restituisce false se non c'è ancora una musica scelta.
  Future<bool> toggleMute() async {
    if (!state.hasTrack) return false;
    state = state.copyWith(muted: !state.muted);
    await _store.write({'muted': state.muted});
    await _sync();
    return true;
  }

  /// Sceglie un nuovo file dal telefono e lo fa partire.
  Future<void> pickTrack() async {
    state = state.copyWith(busy: true);
    try {
      final imported = await _store.importTrack();
      if (imported == null) return;
      final (path, name) = imported;
      final old = _path;
      if (state.playing) {
        await _engine.pause();
        state = state.copyWith(playing: false);
      }
      await _engine.load(path);
      await _engine.setVolume(state.volume);
      _path = path;
      if (old != null && old != path) await _store.deleteTrack(old);
      await _store.write({'path': path, 'name': name, 'ms': 0, 'muted': false});
      state = state.copyWith(trackName: name, muted: false);
    } finally {
      state = state.copyWith(busy: false);
      await _sync();
    }
  }

  Future<void> removeTrack() async {
    await _engine.stop();
    final old = _path;
    _path = null;
    if (old != null) await _store.deleteTrack(old);
    await _store.write({'path': null, 'name': null, 'ms': null});
    _savePosition?.cancel();
    _savePosition = null;
    state = state.copyWith(clearTrack: true, playing: false);
  }

  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await _engine.setVolume(volume);
    await _store.write({'volume': volume});
  }

  Future<void> setAutoplay(bool value) async {
    state = state.copyWith(autoplay: value);
    await _store.write({'autoplay': value});
  }
}
