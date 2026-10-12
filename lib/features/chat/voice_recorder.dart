import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'chat_repository.dart';

/// Crea il registratore dei vocali della chat (nei test se ne usa uno finto).
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (ref) => VoiceRecorder.new,
);

/// Registra un messaggio vocale (AAC in un file .m4a temporaneo), come su Telegram:
/// si tiene premuto il microfono, si rilascia per inviare.
class VoiceRecorder {
  AudioRecorder? _recorder;
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  /// Il permesso del microfono; con [request] il sistema lo chiede se manca.
  Future<bool> hasPermission({bool request = false}) async {
    if (kIsWeb) return false;
    try {
      _recorder ??= AudioRecorder();
      return await _recorder!.hasPermission(request: request);
    } catch (_) {
      return false;
    }
  }

  /// Avvia la registrazione; false se manca il permesso del microfono (o sul web).
  /// Con [requestPermission] false il permesso non si chiede: chi registra tenendo
  /// premuto lo chiede prima, perché il dialogo del sistema interrompe il gesto.
  Future<bool> start({bool requestPermission = true}) async {
    if (!await hasPermission(request: requestPermission)) return false;
    final recorder = _recorder;
    if (recorder == null) return false;
    final dir = await getTemporaryDirectory();
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: '${dir.path}/vocale_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    // Chiuso mentre partiva: niente registrazione.
    if (!identical(recorder, _recorder)) return false;
    _startedAt = DateTime.now();
    return true;
  }

  /// Ferma la registrazione e restituisce il file con la durata in secondi
  /// (null se è troppo corta per valere un messaggio). Con [keepFile] il file
  /// temporaneo resta sul telefono (per riascoltarlo prima di inviarlo).
  Future<({Uint8List bytes, int seconds, String path})?> stop({
    int maxSeconds = maxVoiceSeconds,
    bool keepFile = false,
  }) async {
    final started = _startedAt;
    _startedAt = null;
    final path = await _recorder?.stop();
    if (path == null || started == null) return null;
    final file = File(path);
    // Il file resta solo se serve davvero (registrazione valida e keepFile):
    // uno vuoto o troppo corto si butta comunque.
    var keep = false;
    try {
      final bytes = await file.readAsBytes();
      final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
      if (bytes.isEmpty || seconds < 1) return null;
      keep = keepFile;
      return (
        bytes: bytes,
        seconds: seconds.round().clamp(1, maxSeconds),
        path: path,
      );
    } finally {
      if (!keep) {
        try {
          await file.delete();
        } catch (_) {}
      }
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
