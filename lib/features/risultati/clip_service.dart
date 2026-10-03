import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

/// Durata massima delle clip caricate dal Direttivo.
const maxClipSeconds = 15;

class PreparedClip {
  const PreparedClip(this.bytes, this.durationS);
  final Uint8List bytes;
  final int durationS;
}

/// Taglia (max 15s a partire da [startS]) e comprime una clip prima dell'upload.
///
/// Usa le API video native del telefono (MediaCodec su Android, AVFoundation su iOS):
/// nessuna libreria FFmpeg, file finale a qualità media (~3–5 MB per 15s).
class ClipService {
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Durata del video in secondi.
  static Future<double> durationOf(String path) async {
    final info = await VideoCompress.getMediaInfo(path);
    return (info.duration ?? 0) / 1000;
  }

  static Future<PreparedClip> prepare(
    String path, {
    required int startS,
  }) async {
    final total = await durationOf(path);
    final int start = startS.clamp(0, max(0, total.floor() - 1));
    final length = min<double>(total - start, maxClipSeconds.toDouble());

    // Il plugin interpreta "duration" in modo diverso sulle due piattaforme:
    // iOS = durata della clip, Android = secondi da tagliare dalla fine del video.
    final int durationArg = Platform.isAndroid
        ? max(0, (total - start - length).floor())
        : length.ceil();

    final info = await VideoCompress.compressVideo(
      path,
      quality: VideoQuality.MediumQuality,
      startTime: start,
      duration: durationArg,
      includeAudio: true,
      deleteOrigin: false,
    );
    final file = info?.file;
    if (file == null) {
      throw const ClipException('Compressione del video non riuscita.');
    }

    final seconds = ((info!.duration ?? length * 1000) / 1000).round();
    if (seconds > maxClipSeconds + 1) {
      throw const ClipException(
        'La clip supera i 15 secondi: riprova scegliendo un altro inizio.',
      );
    }
    final bytes = await file.readAsBytes();
    await VideoCompress.deleteAllCache();
    return PreparedClip(bytes, seconds.clamp(1, maxClipSeconds));
  }
}

class ClipException implements Exception {
  const ClipException(this.message);
  final String message;
  @override
  String toString() => message;
}
