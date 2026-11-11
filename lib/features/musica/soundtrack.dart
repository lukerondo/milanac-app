import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio_focus.dart';
import '../../core/config.dart';
import '../intro/intro_state.dart';
import 'club_track.dart';

/// Da dove arriva la musica di sottofondo.
enum SoundtrackSource {
  /// La colonna sonora del club (canzoni strumentali suonate da noi): la scelta
  /// di partenza per tutti.
  club,

  /// Un file audio scelto dal proprio telefono.
  file,

  /// Musica tolta da chi usa l'app.
  none,
}

/// Musica di sottofondo dell'app.
///
/// Di partenza suona la colonna sonora del club ([ClubTrack]): il telefono la scarica
/// una volta e poi la suona dal file. In alternativa ognuno sceglie un file audio dal
/// proprio telefono (es. una compilation di canzoni FIFA scaricata): l'app ne tiene
/// una copia privata. La musica va in loop e si mette in pausa con il pulsante muto.
class SoundtrackState {
  const SoundtrackState({
    this.trackName,
    this.muted = false,
    this.playing = false,
    this.volume = .5,
    this.autoplay = true,
    this.busy = false,
    this.source = SoundtrackSource.club,
    this.download,
    this.downloadFailed = false,
  });

  /// Nome del brano nel lettore (null = nessuna musica pronta).
  final String? trackName;
  final bool muted;
  final bool playing;
  final double volume;

  /// Riparte da sola all'apertura dell'app (se non è in muto).
  final bool autoplay;
  final bool busy;
  final SoundtrackSource source;

  /// Download della colonna sonora del club in corso: avanzamento da 0 a 1.
  final double? download;

  /// La colonna sonora del club non si è potuta scaricare (niente rete).
  final bool downloadFailed;

  bool get hasTrack => trackName != null;
  bool get isClub => source == SoundtrackSource.club;

  SoundtrackState copyWith({
    String? trackName,
    bool clearTrack = false,
    bool? muted,
    bool? playing,
    double? volume,
    bool? autoplay,
    bool? busy,
    SoundtrackSource? source,
    double? download,
    bool clearDownload = false,
    bool? downloadFailed,
  }) => SoundtrackState(
    trackName: clearTrack ? null : trackName ?? this.trackName,
    muted: muted ?? this.muted,
    playing: playing ?? this.playing,
    volume: volume ?? this.volume,
    autoplay: autoplay ?? this.autoplay,
    busy: busy ?? this.busy,
    source: source ?? this.source,
    download: clearDownload ? null : download ?? this.download,
    downloadFailed: downloadFailed ?? this.downloadFailed,
  );
}

/// Riproduttore: just_audio sul telefono, muto nei test e nella demo.
abstract class SoundtrackEngine {
  /// Carica un file del telefono o un indirizzo web (la colonna sonora del club
  /// nel browser).
  Future<void> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Duration get position;

  /// Durata del brano caricato (null se non si sa, come nella demo e nei test).
  Duration? get duration;
  Future<void> dispose();

  /// Chiamato quando [play] non riesce a far partire la musica (nel browser resta
  /// bloccata finché non si tocca la pagina).
  void Function()? onPlayFailed;
}

class JustAudioEngine implements SoundtrackEngine {
  final _player = AudioPlayer();

  @override
  void Function()? onPlayFailed;

  @override
  Future<void> load(String path) async {
    if (path.startsWith('https://') || path.startsWith('http://')) {
      await _player.setUrl(path);
    } else {
      await _player.setFilePath(path);
    }
    await _player.setLoopMode(LoopMode.one);
  }

  // play() di just_audio termina solo quando la riproduzione si ferma: non va atteso.
  // Se il lettore non parte (il browser blocca l'audio prima di un tocco) torna
  // in pausa, così il tentativo dopo riparte davvero.
  @override
  Future<void> play() async => unawaited(
    _player.play().catchError((Object _) async {
      await _player.pause();
      onPlayFailed?.call();
    }),
  );
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
  Duration? get duration => _player.duration;
  @override
  Future<void> dispose() => _player.dispose();
}

class SilentEngine implements SoundtrackEngine {
  @override
  void Function()? onPlayFailed;
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
  Duration? get duration => null;
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

  /// La colonna sonora del club: il file sul telefono, scaricato la prima volta
  /// (con l'avanzamento da 0 a 1 in [onProgress]), o nel browser l'indirizzo da cui
  /// si ascolta.
  Future<String> clubTrack({void Function(double progress)? onProgress});
}

class DeviceSoundtrackStore implements SoundtrackStore {
  static const _prefix = 'soundtrack.';
  final _prefs = SharedPreferencesAsync();
  final _club = ClubTrackCache();

  @override
  Future<Map<String, Object?>> read() async {
    final all = await _prefs.getAll(
      allowList: {
        for (final k in [
          'source',
          'path',
          'name',
          'muted',
          'volume',
          'autoplay',
          'ms',
        ])
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
    try {
      final sink = target.openWrite();
      await sink.addStream(picked.readAsByteStream());
      await sink.close();
    } catch (_) {
      // Copia a metà (spazio finito, file non leggibile): non resta sul telefono.
      if (await target.exists()) await target.delete();
      rethrow;
    }
    return (target.path, picked.name);
  }

  @override
  Future<void> deleteTrack(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<String> clubTrack({
    void Function(double progress)? onProgress,
  }) async => kIsWeb ? ClubTrack.url : _club.path(onProgress: onProgress);
}

/// Versione in memoria per la demo e i test.
///
/// Nella demo il lettore è muto ([SilentEngine]): la colonna sonora del club parte
/// tolta (si rimette con un tocco), così nelle prove dell'app intera il lettore non
/// resta acceso a fine prova.
class MemorySoundtrackStore implements SoundtrackStore {
  final values = <String, Object?>{'source': 'none'};

  @override
  Future<Map<String, Object?>> read() async => Map.of(values);
  @override
  Future<void> write(Map<String, Object?> v) async => values.addAll(v);
  @override
  Future<(String, String)?> importTrack() async =>
      ('/demo/fifa.mp3', 'Canzoni iconiche FIFA.mp3');
  @override
  Future<void> deleteTrack(String path) async {}
  @override
  Future<String> clubTrack({
    void Function(double progress)? onProgress,
  }) async => '/demo/canzoni_autoprodotte.mp3';
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
  /// Il file (o l'indirizzo) nel lettore.
  String? _path;

  /// Punto da cui riprendere la colonna sonora del club appena è pronta.
  Duration? _resumeAt;
  bool _inForeground = true;
  bool _retryOnTap = false;
  Timer? _savePosition;
  AppLifecycleListener? _lifecycle;
  Future<void> _queue = Future.value();
  Future<void>? _clubLoad;

  SoundtrackEngine get _engine => ref.read(soundtrackEngineProvider);
  SoundtrackStore get _store => ref.read(soundtrackStoreProvider);

  @override
  SoundtrackState build() {
    // La musica parte solo dopo il video di benvenuto.
    ref.listen(introDoneProvider, (_, done) {
      if (done) _sync();
    });
    // Vocali, replay e stanza vocale: la musica resta in pausa finché qualcuno usa
    // l'audio e riprende da sola quando hanno finito tutti.
    ref.listen(audioFocusProvider, (_, _) => _sync());
    final engine = _engine..onPlayFailed = _playFailed;
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _inForeground = false;
        _sync();
      },
      onShow: () {
        _inForeground = true;
        // Colonna sonora del club non scaricata (mancava la rete): si riprova.
        if (state.isClub && state.downloadFailed) {
          unawaited(retryClubTrack());
        } else {
          _sync();
        }
      },
    );
    ref.onDispose(() {
      engine.onPlayFailed = null;
      _lifecycle?.dispose();
      _savePosition?.cancel();
      if (_retryOnTap) {
        GestureBinding.instance.pointerRouter.removeGlobalRoute(_retryAfterTap);
      }
    });
    Future.microtask(_restore);
    return const SoundtrackState(busy: true);
  }

  /// Le operazioni sul lettore si fanno una alla volta, nell'ordine in cui arrivano:
  /// due richieste insieme (l'app va in secondo piano mentre parte un vocale...)
  /// non lasciano più la musica accesa in muto o ferma senza motivo.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _restore() async {
    await _serialized(() async {
      if (!ref.mounted) return;
      Map<String, Object?> saved;
      try {
        saved = await _store.read();
      } catch (_) {
        saved = const {};
      }
      final path = saved['path'] as String?;
      final volume = (saved['volume'] as num?)?.toDouble() ?? .5;
      final autoplay = saved['autoplay'] as bool? ?? true;
      final ms = saved['ms'] as int?;
      _resumeAt = ms == null ? null : Duration(milliseconds: ms);
      state = state.copyWith(
        volume: volume,
        autoplay: autoplay,
        // All'apertura riparte solo con l'avvio automatico attivo.
        muted: (saved['muted'] as bool? ?? false) || !autoplay,
        source: switch (saved['source']) {
          'club' => SoundtrackSource.club,
          'file' => SoundtrackSource.file,
          'none' => SoundtrackSource.none,
          // Salvato prima della colonna sonora del club: chi aveva scelto un file
          // lo ritrova, gli altri sentono quella del club.
          _ => path != null ? SoundtrackSource.file : SoundtrackSource.club,
        },
      );
      if (state.source != SoundtrackSource.file) return;
      try {
        if (path == null) throw StateError('Nessun file salvato');
        await _engine.load(path);
        await _engine.setVolume(volume);
        if (_resumeAt case final at?) await _engine.seek(at);
        _resumeAt = null;
        _path = path;
        state = state.copyWith(trackName: saved['name'] as String? ?? 'Musica');
      } catch (_) {
        // File sparito o non leggibile: torna la colonna sonora del club.
        _path = null;
        _resumeAt = null;
        state = state.copyWith(clearTrack: true, source: SoundtrackSource.club);
        await _saveQuietly({
          'source': 'club',
          'path': null,
          'name': null,
          'ms': null,
        });
      }
    });
    if (!ref.mounted) return;
    state = state.copyWith(busy: false);
    await _settle();
  }

  /// Dopo un cambio: se tocca alla colonna sonora del club e non è ancora nel
  /// lettore la si prepara (poi parte da sola), altrimenti si allinea il lettore.
  Future<void> _settle() async {
    if (state.isClub && !state.hasTrack && !state.downloadFailed) {
      await _loadClub();
    } else {
      await _sync();
    }
  }

  /// Prepara la colonna sonora del club: la prima volta la scarica (con
  /// l'avanzamento), poi la mette nel lettore e la fa partire.
  Future<void> _loadClub() =>
      _clubLoad ??= _doLoadClub().whenComplete(() => _clubLoad = null);

  Future<void> _doLoadClub() async {
    state = state.copyWith(downloadFailed: false);
    final String path;
    try {
      path = await _store.clubTrack(
        onProgress: (p) {
          if (ref.mounted && state.isClub) {
            state = state.copyWith(download: p);
          }
        },
      );
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          clearDownload: true,
          downloadFailed: state.isClub,
        );
      }
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(clearDownload: true);
    await _serialized(() async {
      // Nel frattempo si è scelto un file o si è tolta la musica.
      if (!ref.mounted || !state.isClub || _path == path) return;
      try {
        await _engine.load(path);
        await _engine.setVolume(state.volume);
        final at = _resumeAt;
        _resumeAt = null;
        if (at != null) await _engine.seek(at);
        _path = path;
        state = state.copyWith(trackName: ClubTrack.title);
      } catch (_) {
        // Copia rovinata (o indirizzo irraggiungibile nel browser): al prossimo
        // tentativo si scarica di nuovo.
        await _deleteQuietly(path);
        state = state.copyWith(downloadFailed: true);
      }
    });
    await _sync();
  }

  /// Suona solo se c'è un file, non è in muto, l'app è in primo piano, l'intro è
  /// finita e nessun altro sta usando l'audio.
  Future<void> _sync() => _serialized(() async {
    if (!ref.mounted) return;
    final shouldPlay =
        _path != null &&
        !state.muted &&
        _inForeground &&
        ref.read(introDoneProvider) &&
        ref.read(audioFocusProvider).isEmpty;
    if (shouldPlay == state.playing) return;
    try {
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
    } catch (_) {
      // Il lettore non ha risposto: si riprova alla prossima richiesta.
    }
  });

  /// Il lettore non è partito: nel browser l'audio resta bloccato finché non si
  /// tocca la pagina. Al primo tocco si riprova.
  void _playFailed() {
    if (!ref.mounted) return;
    unawaited(
      _serialized(() async {
        if (!ref.mounted) return;
        _savePosition?.cancel();
        _savePosition = null;
        state = state.copyWith(playing: false);
      }),
    );
    if (_retryOnTap) return;
    _retryOnTap = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_retryAfterTap);
  }

  void _retryAfterTap(PointerEvent event) {
    if (event is! PointerUpEvent) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_retryAfterTap);
    _retryOnTap = false;
    if (ref.mounted) unawaited(_sync());
  }

  Future<void> _rememberPosition() =>
      _store.write({'ms': _engine.position.inMilliseconds});

  Future<void> _deleteQuietly(String path) async {
    try {
      await _store.deleteTrack(path);
    } catch (_) {}
  }

  Future<void> _saveQuietly(Map<String, Object?> values) async {
    try {
      await _store.write(values);
    } catch (_) {}
  }

  /// Pulsante muto. Restituisce false se non c'è ancora una musica pronta.
  Future<bool> toggleMute() async {
    if (!state.hasTrack) return false;
    state = state.copyWith(muted: !state.muted);
    await _store.write({'muted': state.muted});
    await _sync();
    return true;
  }

  /// Sceglie un nuovo file dal telefono e lo fa partire. Se il telefono non lo sa
  /// riprodurre (es. .ogg o .opus su iPhone) la copia si cancella, torna la musica
  /// di prima e l'errore arriva a chi ha chiamato.
  Future<void> pickTrack() async {
    state = state.copyWith(busy: true);
    try {
      final imported = await _store.importTrack();
      if (imported == null) return;
      await _serialized(() => _switchTo(imported.$1, imported.$2));
    } finally {
      if (ref.mounted) {
        state = state.copyWith(busy: false);
        await _settle();
      }
    }
  }

  Future<void> _switchTo(String path, String name) async {
    final old = _path;
    // La colonna sonora del club resta sul telefono: si cancella solo un vecchio
    // file scelto dal telefono.
    final oldFile = state.source == SoundtrackSource.file ? old : null;
    final at = _engine.position;
    if (state.playing) {
      await _engine.pause();
      _savePosition?.cancel();
      _savePosition = null;
      state = state.copyWith(playing: false);
    }
    try {
      await _engine.load(path);
      await _engine.setVolume(state.volume);
    } catch (_) {
      await _deleteQuietly(path);
      await _reload(old, at);
      rethrow;
    }
    _path = path;
    _resumeAt = null;
    if (oldFile != null && oldFile != path) await _deleteQuietly(oldFile);
    await _store.write({
      'source': 'file',
      'path': path,
      'name': name,
      'ms': 0,
      'muted': false,
    });
    state = state.copyWith(
      source: SoundtrackSource.file,
      trackName: name,
      muted: false,
      clearDownload: true,
      downloadFailed: false,
    );
  }

  /// Rimette la musica di prima dopo un file nuovo che non si riesce a leggere;
  /// se non si può, torna la colonna sonora del club (da riscaricare).
  Future<void> _reload(String? old, Duration at) async {
    if (old == null) return;
    try {
      await _engine.load(old);
      await _engine.setVolume(state.volume);
      await _engine.seek(at);
    } catch (_) {
      _path = null;
      await _deleteQuietly(old);
      await _store.write({
        'source': 'club',
        'path': null,
        'name': null,
        'ms': null,
      });
      state = state.copyWith(clearTrack: true, source: SoundtrackSource.club);
    }
  }

  /// Torna alla colonna sonora del club (dopo un file del telefono o dopo averla
  /// tolta) e la fa partire.
  Future<void> useClubTrack() async {
    await _serialized(() async {
      if (!ref.mounted || state.isClub) return;
      final oldFile = state.source == SoundtrackSource.file ? _path : null;
      try {
        await _engine.stop();
      } catch (_) {}
      _path = null;
      _resumeAt = null;
      _savePosition?.cancel();
      _savePosition = null;
      state = state.copyWith(
        source: SoundtrackSource.club,
        clearTrack: true,
        playing: false,
        muted: false,
        downloadFailed: false,
      );
      await _store.write({
        'source': 'club',
        'path': null,
        'name': null,
        'ms': null,
        'muted': false,
      });
      if (oldFile != null) await _deleteQuietly(oldFile);
    });
    if (ref.mounted) await _settle();
  }

  /// Nuovo tentativo dopo un download della colonna sonora del club non riuscito.
  Future<void> retryClubTrack() async {
    if (!state.isClub || state.hasTrack) return;
    state = state.copyWith(downloadFailed: false);
    await _loadClub();
  }

  /// Toglie la musica (anche la colonna sonora del club, finché non la si rimette).
  Future<void> removeTrack() => _serialized(() async {
    try {
      await _engine.stop();
    } catch (_) {}
    final oldFile = state.source == SoundtrackSource.file ? _path : null;
    _path = null;
    _resumeAt = null;
    _savePosition?.cancel();
    _savePosition = null;
    state = state.copyWith(
      clearTrack: true,
      playing: false,
      source: SoundtrackSource.none,
      clearDownload: true,
      downloadFailed: false,
    );
    if (oldFile != null) await _deleteQuietly(oldFile);
    await _store.write({
      'source': 'none',
      'path': null,
      'name': null,
      'ms': null,
    });
  });

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
