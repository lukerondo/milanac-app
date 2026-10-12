import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../features/rosa/member.dart';
import '../features/volto/face_view.dart';

const avatarsBucket = 'avatars';

/// Solo demo: foto caricate tenute in memoria (percorso → contenuto).
final demoPhotos = <String, Uint8List>{};

/// URL firmato della foto caricata dal membro nel bucket privato "avatars". Vale
/// 7 giorni: si riusa per 6, poi (quando nessuno lo mostra più) se ne chiede uno nuovo.
final photoUrlProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  path,
) async {
  if (AppConfig.isDemo) return null;
  final keep = ref.keepAlive();
  final timer = Timer(const Duration(days: 6), keep.close);
  ref.onDispose(timer.cancel);
  try {
    return await ref
        .read(supabaseProvider)
        .storage
        .from(avatarsBucket)
        .createSignedUrl(path, 7 * 24 * 3600);
  } catch (_) {
    keep.close(); // un errore non resta in memoria
    rethrow;
  }
});

/// Foto del membro: quella caricata dalle Impostazioni, altrimenti quella dell'account social.
ImageProvider? memberPhoto(WidgetRef ref, Member m) {
  final path = m.avatarPath;
  if (path != null) {
    final local = demoPhotos[path];
    if (local != null) return MemoryImage(local);
    final url = ref.watch(photoUrlProvider(path)).value;
    if (url != null) return NetworkImage(url);
  }
  final social = m.avatarUrl;
  return social == null || social.isEmpty ? null : NetworkImage(social);
}

/// Avatar tondo: foto se c'è, altrimenti numero di maglia o iniziale. Senza foto
/// usa i colori del tema ([background] e [foreground] per i fondi sempre scuri).
class MemberAvatar extends ConsumerWidget {
  const MemberAvatar({
    super.key,
    required this.member,
    this.radius = 22,
    this.showNumber = true,
    this.background,
    this.foreground,
  });
  final Member member;
  final double radius;
  final bool showNumber;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final fill = background ?? p.surfaceHigher;
    // Il volto disegnato ha la precedenza su qualsiasi foto.
    final face = member.face;
    if (face != null) {
      return ClipOval(
        child: FaceView(
          face: face,
          size: radius * 2,
          crop: FaceCrop.head,
          background: fill,
        ),
      );
    }
    final photo = memberPhoto(ref, member);
    final label = showNumber && member.shirtNumber != null
        ? '${member.shirtNumber}'
        : member.displayName.isEmpty
        ? '?'
        : member.displayName.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: fill,
      backgroundImage: photo,
      child: photo == null
          ? Text(
              label,
              style: TextStyle(
                fontFamily: sportFont,
                fontWeight: FontWeight.w600,
                color: foreground ?? p.textSecondary,
                fontSize: (radius * .75).clamp(12, 48).toDouble(),
                height: 1,
              ),
            )
          : null,
    );
  }
}

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
