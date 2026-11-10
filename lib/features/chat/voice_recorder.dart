import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import 'chat_repository.dart';
import 'voice_file_io.dart' if (dart.library.js_interop) 'voice_file_web.dart';

/// Crea il registratore dei vocali della chat (nei test se ne usa uno finto).
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (ref) => VoiceRecorder.new,
);

/// Come si registra sul telefono: AAC in un file .m4a.
const phoneRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 64000,
  sampleRate: 44100,
  numChannels: 1,
);

/// Come si registra nel browser, perché il vocale si senta anche sui telefoni: AAC
/// (lo stesso formato dell'app) dove il browser lo sa fare (Chrome ed Edge su Windows e
/// Mac, Safari), altrimenti WAV, che suona ovunque ma pesa: la qualità scende quanto
/// basta per stare nei 5 MB della chat anche alla durata massima ([maxSeconds]).
Future<RecordConfig> webRecordConfig(
  Future<bool> Function(AudioEncoder) isSupported,
  int maxSeconds,
) async {
  try {
    if (await isSupported(AudioEncoder.aacLc)) return phoneRecordConfig;
  } catch (_) {}
  // WAV mono a 16 bit: 2 byte per campione.
  const limit = 5000000;
  return RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: maxSeconds * 16000 * 2 <= limit ? 16000 : 8000,
    numChannels: 1,
  );
}

/// Registra un messaggio vocale, come su Telegram: si tiene premuto il microfono, si
/// rilascia per inviare. Sul telefono in un file temporaneo, nel browser in memoria.
class VoiceRecorder {
  AudioRecorder? _recorder;
  DateTime? _startedAt;

  /// Nel browser: il permesso è già stato dato in questa pagina. Non tutti i browser
  /// lo lasciano chiedere senza far comparire la richiesta (Firefox).
  var _grantedHere = false;

  bool get isRecording => _startedAt != null;

  /// Il permesso del microfono; con [request] il sistema lo chiede se manca.
  Future<bool> hasPermission({bool request = false}) async {
    if (kIsWeb && _grantedHere) return true;
    try {
      _recorder ??= AudioRecorder();
      final granted = await _recorder!.hasPermission(request: request);
      if (granted) _grantedHere = true;
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Avvia la registrazione; false se manca il permesso del microfono. Con
  /// [requestPermission] false il permesso non si chiede: chi registra tenendo
  /// premuto lo chiede prima, perché il dialogo del sistema interrompe il gesto.
  /// [maxSeconds] è la durata massima prevista (nel browser decide la qualità).
  Future<bool> start({
    bool requestPermission = true,
    int maxSeconds = maxVoiceSeconds,
  }) async {
    if (!await hasPermission(request: requestPermission)) return false;
    final recorder = _recorder;
    if (recorder == null) return false;
    final config = kIsWeb
        ? await webRecordConfig(recorder.isEncoderSupported, maxSeconds)
        : phoneRecordConfig;
    await recorder.start(
      config,
      path: await recordingPath(
        'vocale_${DateTime.now().millisecondsSinceEpoch}.m4a',
      ),
    );
    // Chiuso mentre partiva: niente registrazione.
    if (!identical(recorder, _recorder)) return false;
    _startedAt = DateTime.now();
    return true;
  }

  /// Ferma la registrazione e restituisce l'audio con la durata in secondi
  /// (null se è troppo corta per valere un messaggio). Con [keepFile] la
  /// registrazione resta (per riascoltarla prima di inviarla): chi la tiene la butta
  /// poi con `discardRecording`.
  Future<({Uint8List bytes, int seconds, String path})?> stop({
    int maxSeconds = maxVoiceSeconds,
    bool keepFile = false,
  }) async {
    final started = _startedAt;
    _startedAt = null;
    final path = await _recorder?.stop();
    if (path == null || started == null) return null;
    // Il file resta solo se serve davvero (registrazione valida e keepFile):
    // uno vuoto o troppo corto si butta comunque.
    var keep = false;
    try {
      final bytes = await readRecording(path);
      final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
      if (bytes.isEmpty || seconds < 1) return null;
      keep = keepFile;
      return (
        bytes: bytes,
        seconds: seconds.round().clamp(1, maxSeconds),
        path: path,
      );
    } finally {
      if (!keep) await discardRecording(path);
    }
  }

  /// Annulla: il file registrato viene buttato.
  Future<void> cancel() async {
    _startedAt = null;
    try {
      await _recorder?.cancel();
    } catch (_) {}
  }

  /// Chiude il registratore (una registrazione in corso si butta).
  void dispose() {
    final recorder = _recorder;
    final recording = _startedAt != null;
    _recorder = null;
    _startedAt = null;
    if (recorder == null) return;
    unawaited(() async {
      try {
        if (recording) await recorder.cancel();
        await recorder.dispose();
      } catch (_) {}
    }());
  }
}
