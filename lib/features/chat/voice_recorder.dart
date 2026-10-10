import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'chat_repository.dart';

/// Registra un messaggio vocale (AAC in un file .m4a temporaneo), come su Telegram:
/// si tiene premuto il microfono, si rilascia per inviare.
class VoiceRecorder {
  AudioRecorder? _recorder;
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  /// Avvia la registrazione; false se manca il permesso del microfono (o sul web).
  Future<bool> start() async {
    if (kIsWeb) return false;
    _recorder ??= AudioRecorder();
    if (!await _recorder!.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: '${dir.path}/vocale_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
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
    try {
      final bytes = await file.readAsBytes();
      final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
      if (bytes.isEmpty || seconds < 1) return null;
      return (
        bytes: bytes,
        seconds: seconds.round().clamp(1, maxSeconds),
        path: path,
      );
    } finally {
      if (!keepFile) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  /// Annulla: il file registrato viene buttato.
  Future<void> cancel() async {
    _startedAt = null;
    await _recorder?.cancel();
  }

  void dispose() => _recorder?.dispose();
}
