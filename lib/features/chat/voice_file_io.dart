import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Dove sta una registrazione appena fatta: sul telefono un file temporaneo (qui), nel
/// browser un indirizzo in memoria (`voice_file_web.dart`).

/// Il percorso del file in cui registrare.
Future<String> recordingPath(String name) async =>
    '${(await getTemporaryDirectory()).path}/$name';

Future<Uint8List> readRecording(String path) => File(path).readAsBytes();

/// Butta la registrazione (un file già sparito non è un errore).
Future<void> discardRecording(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}
