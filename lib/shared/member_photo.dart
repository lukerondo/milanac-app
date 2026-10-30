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

/// Copia sul telefono delle foto dei membri: il percorso nel bucket cambia a ogni foto
/// nuova (`<id>/foto_<ms>.jpg`), quindi una foto salvata vale per sempre e non si
/// riscarica a ogni avvio (e si vede anche senza rete).
class PhotoDiskCache {
  @visibleForTesting
  static Future<Directory> Function() directory = () async =>
      Directory('${(await getApplicationSupportDirectory()).path}/foto');

  static String _name(String path) => path.replaceAll('/', '_');

  static Future<Uint8List?> read(String path) async {
    try {
      final f = File('${(await directory()).path}/${_name(path)}');
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  /// Salva la foto e toglie quelle vecchie dello stesso membro.
  static Future<void> write(String path, Uint8List bytes) async {
    try {
      final dir = await directory();
      await dir.create(recursive: true);
      final name = _name(path);
      final owner = '${name.split('_').first}_';
      await for (final e in dir.list()) {
        final other = e.uri.pathSegments.last;
        if (other.startsWith(owner) && other != name) await e.delete();
      }
      await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    } catch (_) {}
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
        localPhotos[path] = bytes;
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
