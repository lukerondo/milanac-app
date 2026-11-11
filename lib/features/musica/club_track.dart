import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// La colonna sonora del club: canzoni strumentali suonate da noi, un unico mp3 di
/// 36 minuti (circa 22 MB) pubblicato con il sito in `sito/audio/`.
///
/// Non sta dentro l'app: APK e IPA crescerebbero di 22 MB (l'IPA supererebbe i 50 MB
/// di Diawi). Il telefono la scarica la prima volta e poi la suona dal file, anche
/// senza rete; nel browser si ascolta direttamente dall'indirizzo.
abstract final class ClubTrack {
  static const title = 'Canzoni autoprodotte';
  static const url =
      'https://milanacproclub.vercel.app/audio/canzoni_autoprodotte.mp3';
}

/// Copia della colonna sonora del club sul telefono.
///
/// Il file si chiama `colonna_sonora_club_<byte>.mp3`. A ogni apertura si chiede al
/// sito quanto pesa l'mp3 pubblicato: se è cambiato (nuove canzoni) la versione nuova
/// si scarica in silenzio accanto alla vecchia e suona dall'apertura successiva,
/// senza aggiornare l'app.
class ClubTrackCache {
  ClubTrackCache({
    Uri? url,
    Future<Directory> Function()? directory,
    this.timeout = const Duration(seconds: 30),
  }) : url = url ?? Uri.parse(ClubTrack.url),
       _directory = directory ?? getApplicationDocumentsDirectory;

  final Uri url;
  final Future<Directory> Function() _directory;

  /// Attesa massima per la connessione e tra un pezzo e l'altro del download.
  final Duration timeout;

  static final _fileName = RegExp(r'^colonna_sonora_club_(\d+)\.mp3$');
  static const _partial = 'colonna_sonora_club.part';

  Future<File>? _download;

  /// Controllo della versione sul sito, partito dall'ultima [path] (per i test).
  Future<void>? pendingUpdate;

  /// Il percorso del file sul telefono, scaricandolo se ancora non c'è; durante il
  /// download [onProgress] riceve l'avanzamento da 0 a 1.
  Future<String> path({void Function(double progress)? onProgress}) async {
    final dir = await _directory();
    final cached = await _cached(dir);
    if (cached != null) {
      pendingUpdate ??= _checkUpdate(dir, cached);
      return cached.path;
    }
    return (await _fetch(dir, onProgress)).path;
  }

  /// La copia più recente; le altre (versioni vecchie, download interrotti) si
  /// cancellano, se non c'è un download in corso.
  Future<File?> _cached(Directory dir) async {
    final found = <File>[];
    await for (final e in dir.list()) {
      if (e is File && _fileName.hasMatch(_name(e))) found.add(e);
    }
    if (found.isEmpty) return null;
    final dated = [for (final f in found) (f, await f.lastModified())]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (_download == null) {
      for (final (old, _) in dated.skip(1)) {
        await _deleteQuietly(old);
      }
      await _deleteQuietly(File('${dir.path}/$_partial'));
    }
    return dated.first.$1;
  }

  Future<void> _checkUpdate(Directory dir, File cached) async {
    try {
      final have = int.parse(_fileName.firstMatch(_name(cached))!.group(1)!);
      final online = await _remoteSize();
      if (online != null && online != have) await _fetch(dir, null);
    } catch (_) {
      // Niente rete o sito irraggiungibile: si riprova alla prossima apertura.
    }
  }

  Future<int?> _remoteSize() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.headUrl(url).timeout(timeout);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == HttpStatus.ok && res.contentLength > 0
          ? res.contentLength
          : null;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _fetch(Directory dir, void Function(double)? onProgress) =>
      _download ??= _downloadTo(
        dir,
        onProgress,
      ).whenComplete(() => _download = null);

  Future<File> _downloadTo(
    Directory dir,
    void Function(double)? onProgress,
  ) async {
    final part = File('${dir.path}/$_partial');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(url).timeout(timeout);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final res = await req.close().timeout(timeout);
      // Una pagina (errore, sito non ancora pubblicato) non è musica.
      if (res.statusCode != HttpStatus.ok ||
          res.headers.contentType?.primaryType == 'text') {
        await res.drain<void>().catchError((_) {});
        throw HttpException(
          'Colonna sonora non disponibile (${res.statusCode})',
          uri: url,
        );
      }
      final total = res.contentLength;
      var received = 0;
      onProgress?.call(0);
      final sink = part.openWrite();
      try {
        await for (final chunk in res.timeout(timeout)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || (total > 0 && received != total)) {
        throw HttpException('Download incompleto', uri: url);
      }
      return await part.rename('${dir.path}/colonna_sonora_club_$received.mp3');
    } catch (_) {
      await _deleteQuietly(part);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static String _name(File f) => f.uri.pathSegments.last;

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
