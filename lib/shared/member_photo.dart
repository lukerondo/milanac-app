import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../features/rosa/member.dart';
import 'silhouette.dart';

const avatarsBucket = 'avatars';

/// Foto già in memoria (percorso → contenuto): quelle appena caricate da questo
/// telefono, quelle lette dalla copia sul telefono e, nella demo, tutte.
final localPhotos = <String, Uint8List>{};
final _addedAt = <String, DateTime>{};

/// Mette in memoria una foto (appena caricata o letta): si vede subito, senza scaricarla.
void rememberPhoto(String path, Uint8List bytes) {
  localPhotos[path] = bytes;
  _addedAt[path] = DateTime.now();
}

/// Copia sul telefono delle foto dei membri, nella cartella della cache (fuori dai
/// backup, il sistema può svuotarla): il percorso nel bucket cambia a ogni foto nuova
/// (`<id>/foto_<ms>.jpg`), quindi una foto salvata vale finché è quella del membro e
/// non si riscarica a ogni avvio (e si vede anche senza rete).
class PhotoDiskCache {
  @visibleForTesting
  static Future<Directory> Function() directory = () async =>
      Directory('${(await getApplicationCacheDirectory()).path}/foto');

  static String _name(String path) => path.replaceAll('/', '_');

  /// Un JPEG intero (inizio e fine): un file scritto a metà si butta.
  static bool _whole(Uint8List b) =>
      b.length > 4 &&
      b[0] == 0xFF &&
      b[1] == 0xD8 &&
      b[b.length - 2] == 0xFF &&
      b[b.length - 1] == 0xD9;

  static Future<Uint8List?> read(String path) async {
    try {
      final f = File('${(await directory()).path}/${_name(path)}');
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      if (_whole(bytes)) return bytes;
      await f.delete();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Salva la foto (prima in un file temporaneo, poi rinominato: mai a metà) e toglie
  /// quelle vecchie dello stesso membro.
  static Future<void> write(String path, Uint8List bytes) async {
    if (!_whole(bytes)) return;
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      final name = _name(path);
      final owner = '${name.split('_').first}_';
      await for (final e in dir.list()) {
        final other = e.uri.pathSegments.last;
        if (other.startsWith(owner) && other != name) await e.delete();
      }
      final tmp = File('${dir.path}/$name.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename('${dir.path}/$name');
    } catch (_) {}
  }

  static Future<void> delete(String path) async {
    localPhotos.remove(path);
    try {
      final f = File('${(await directory()).path}/${_name(path)}');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Tiene solo le foto attuali dei membri della rosa: quelle tolte, sostituite o di
  /// chi ha lasciato il club spariscono anche dal telefono (in memoria restano le foto
  /// appena caricate, che la rosa non ha ancora).
  static Future<void> keepOnly(Set<String> current) async {
    final now = DateTime.now();
    localPhotos.removeWhere(
      (p, _) =>
          !current.contains(p) &&
          now.difference(_addedAt[p] ?? DateTime(2000)) >
              const Duration(minutes: 2),
    );
    try {
      final dir = await directory();
      if (!await dir.exists()) return;
      final keep = current.map(_name).toSet();
      await for (final e in dir.list()) {
        if (!keep.contains(e.uri.pathSegments.last)) await e.delete();
      }
    } catch (_) {}
  }

  /// Cambio di account o uscita: via tutte le foto, in memoria e sul telefono.
  static Future<void> clear() async {
    localPhotos.clear();
    _addedAt.clear();
    try {
      final dir = await directory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static String? _user;

  /// Chiamata quando si sa chi è collegato: con un altro account (o nessuno) le foto
  /// del precedente non restano sul telefono.
  static void forUser(String? userId) {
    if (_user != null && _user != userId) unawaited(clear());
    _user = userId;
  }

  static Set<String>? _lastRoster;

  /// La rosa è arrivata (o è cambiata): si tengono solo le foto attuali.
  static void syncWithRoster(Iterable<String?> paths) {
    final current = {...paths.whereType<String>()};
    if (_lastRoster != null && setEquals(_lastRoster, current)) return;
    _lastRoster = current;
    unawaited(keepOnly(current));
  }
}

/// La foto caricata da un membro (bucket privato "avatars"): prima dalla memoria, poi
/// dalla copia sul telefono, altrimenti scaricata e salvata. Nella demo c'è solo quella
/// in memoria. Un errore non resta: alla prossima richiesta si riprova.
final photoBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, path) async {
      final local = localPhotos[path];
      if (local != null) return local;
      if (AppConfig.isDemo) return null;
      final keep = ref.keepAlive();
      try {
        var bytes = await PhotoDiskCache.read(path);
        if (bytes == null) {
          bytes = await ref
              .read(supabaseProvider)
              .storage
              .from(avatarsBucket)
              .download(path);
          await PhotoDiskCache.write(path, bytes);
        }
        rememberPhoto(path, bytes);
        return bytes;
      } catch (_) {
        keep.close();
        rethrow;
      }
    });

/// La foto del membro, solo quella caricata dalla galleria (mai quella dell'account
/// social): null se non c'è o se non è ancora arrivata. Con [cacheWidth] l'immagine si
/// decodifica piccola (avatar, mini carte).
ImageProvider? photoOf(WidgetRef ref, String? avatarPath, {int? cacheWidth}) {
  if (avatarPath == null) return null;
  final bytes = ref.watch(photoBytesProvider(avatarPath)).value;
  if (bytes == null) return null;
  return ResizeImage.resizeIfNeeded(cacheWidth, null, MemoryImage(bytes));
}

ImageProvider? memberPhoto(WidgetRef ref, Member m, {int? cacheWidth}) =>
    photoOf(ref, m.avatarPath, cacheWidth: cacheWidth);

/// Avatar tondo con la foto del membro; senza foto la sagoma grigia (come sulle carte).
/// [background] e [foreground] per i fondi sempre scuri.
class MemberAvatar extends ConsumerWidget {
  const MemberAvatar({
    super.key,
    required this.member,
    this.radius = 22,
    this.background,
    this.foreground,
  });
  final Member member;
  final double radius;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final photo = memberPhoto(
      ref,
      member,
      cacheWidth: (radius * 2 * dpr).ceil(),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: photo == null
            ? PlayerSilhouette(
                background: background ?? p.surfaceHigher,
                color: foreground ?? p.textSecondary,
              )
            : Image(
                image: photo,
                fit: BoxFit.cover,
                alignment: photoAlignment,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => PlayerSilhouette(
                  background: background ?? p.surfaceHigher,
                  color: foreground ?? p.textSecondary,
                ),
              ),
      ),
    );
  }
}

/// Le foto sono inquadrate 4:5 come il riquadro della carta: nei tondi conta la parte
/// alta, dove sta il viso.
const photoAlignment = Alignment(0, -.45);

/// Bandiera (emoji) da un codice ISO a 2 lettere.
String flagEmoji(String iso2) => String.fromCharCodes(
  iso2.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
);

/// Nazionalità proposte nelle Impostazioni (codice ISO → nome).
const nationalities = {
  'IT': 'Italia',
  'AL': 'Albania',
  'DZ': 'Algeria',
  'AR': 'Argentina',
  'BD': 'Bangladesh',
  'BE': 'Belgio',
  'BR': 'Brasile',
  'CM': 'Camerun',
  'CN': 'Cina',
  'CO': 'Colombia',
  'CI': "Costa d'Avorio",
  'HR': 'Croazia',
  'EC': 'Ecuador',
  'EG': 'Egitto',
  'PH': 'Filippine',
  'FR': 'Francia',
  'DE': 'Germania',
  'GH': 'Ghana',
  'GR': 'Grecia',
  'IN': 'India',
  'IE': 'Irlanda',
  'MA': 'Marocco',
  'MD': 'Moldavia',
  'NG': 'Nigeria',
  'NL': 'Paesi Bassi',
  'PE': 'Perù',
  'PL': 'Polonia',
  'PT': 'Portogallo',
  'GB': 'Regno Unito',
  'RO': 'Romania',
  'SN': 'Senegal',
  'RS': 'Serbia',
  'ES': 'Spagna',
  'LK': 'Sri Lanka',
  'US': 'Stati Uniti',
  'CH': 'Svizzera',
  'TN': 'Tunisia',
  'TR': 'Turchia',
  'UA': 'Ucraina',
  'UY': 'Uruguay',
  'VE': 'Venezuela',
};
