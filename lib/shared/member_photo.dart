import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/providers.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../features/rosa/member.dart';

const avatarsBucket = 'avatars';

/// Solo demo: foto caricate tenute in memoria (percorso → contenuto).
final demoPhotos = <String, Uint8List>{};

/// URL firmato (7 giorni) della foto caricata dal membro nel bucket privato "avatars".
final photoUrlProvider = FutureProvider.family<String?, String>((
  ref,
  path,
) async {
  if (AppConfig.isDemo) return null;
  return ref
      .read(supabaseProvider)
      .storage
      .from(avatarsBucket)
      .createSignedUrl(path, 7 * 24 * 3600);
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

/// Avatar tondo: foto se c'è, altrimenti numero di maglia o iniziale.
class MemberAvatar extends ConsumerWidget {
  const MemberAvatar({
    super.key,
    required this.member,
    this.radius = 22,
    this.showNumber = true,
  });
  final Member member;
  final double radius;
  final bool showNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = memberPhoto(ref, member);
    final label = showNumber && member.shirtNumber != null
        ? '${member.shirtNumber}'
        : member.displayName.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: MilanacColors.red,
      backgroundImage: photo,
      child: photo == null
          ? Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: radius * .7,
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
