import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../volto/face_view.dart';
import 'card_colors.dart';
import 'card_stats.dart';

/// Colori (sopra, sotto, scritte) di una mini carta disegnata nel PDF della
/// formazione: carta speciale o livello dell'overall.
(Color, Color, Color) miniCardColors(int? overall, SpecialCard? special) =>
    switch (special?.kind) {
      CardSpecial.neroOro => CardColors.pdfNeroOro,
      CardSpecial.blu => CardColors.pdfBlu,
      null => switch (tierOf(overall)) {
        CardTier.vuota => CardColors.pdfVuota,
        CardTier.bronzo => CardColors.pdfBronzo,
        CardTier.argento => CardColors.pdfArgento,
        CardTier.oro => CardColors.pdfOro,
        CardTier.rossonera => CardColors.pdfRossonera,
      },
    };

/// Squadre scritte sotto il nome delle mini carte ("MILAN AC", "FUTURO").
String _teamsShort(Set<Team> teams) => [
  for (final t in Team.values)
    if (teams.contains(t)) t.short,
].join(' · ');

/// Altezza di una mini carta (cresce con il testo grande del telefono).
double miniCardHeight(BuildContext context) =>
    99 + 69 * MediaQuery.textScalerOf(context).scale(1);

/// Mini carta del giocatore (Rosa), come la tavola: nero/oro, blu elettrico o
/// normale (scura, con il colore del livello in alto). Overall con il bonus, ruolo,
/// volto, nome e tipo di carta. Colori fissi: è un oggetto di gioco.
/// Etichetta del volo della carta dalla Rosa (mini carta) alla carta grande.
Object cardHeroTag(String memberId) => 'carta-$memberId';

class MiniCard extends ConsumerWidget {
  const MiniCard({super.key, required this.member, this.onTap});
  final Member member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final special = ref.watch(activeSpecialCardProvider(member.id));
    final overall = overallWith(member.overall, special);
    final kind = special?.kind;
    final (bg, fg, roleColor, labelColor) = switch (kind) {
      CardSpecial.neroOro => (
        CardColors.neroOro,
        CardColors.goldText,
        CardColors.goldText,
        CardColors.goldText,
      ),
      CardSpecial.blu => (
        CardColors.blue,
        CardColors.onBlue,
        CardColors.onBlue,
        CardColors.onBlue,
      ),
      null => (
        CardColors.surface,
        CardColors.text,
        CardColors.textMuted,
        CardColors.caption,
      ),
    };
    final label = switch (kind) {
      CardSpecial.neroOro => 'NERO/ORO',
      CardSpecial.blu => 'BLU ELETTRICO',
      null => _teamsShort(member.teams),
    };
    final description = [
      member.displayName,
      ?overall?.toString(),
      if (kind == CardSpecial.neroOro) 'carta nero e oro',
      if (kind == CardSpecial.blu) 'carta blu elettrico',
    ].join(', ');
    return Semantics(
      button: onTap != null,
      label: description,
      onTap: onTap,
      excludeSemantics: true,
      // Aprendola, la carta vola fino a quella grande. Non dalle schede nascoste: la
      // Rosa lasciata aperta in un'altra scheda non fa partire carte da fuori schermo.
      child: HeroMode(
        enabled: TickerMode.valuesOf(context).enabled,
        child: Hero(
          tag: cardHeroTag(member.id),
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: switch (kind) {
                CardSpecial.neroOro => const BorderSide(color: CardColors.gold),
                CardSpecial.blu => BorderSide.none,
                null => const BorderSide(color: CardColors.border),
              },
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kind == null)
                    Container(
                      height: 5,
                      color: CardColors.tier(tierOf(member.overall)),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(8, kind == null ? 6 : 8, 8, 8),
                    child: Column(
                      children: [
                        // Overall (con il bonus) a sinistra, ruolo a destra: si
                        // rimpiccioliscono se lo spazio non basta.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      overall?.toString() ?? '–',
                                      style: TextStyle(
                                        fontFamily: sportFont,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        height: 1,
                                        color: fg,
                                      ),
                                    ),
                                    if (special != null)
                                      Text(
                                        '+${special.bonus}',
                                        style: TextStyle(
                                          fontFamily: sportFont,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          height: 1,
                                          color: fg,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 38),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topRight,
                                child: Text(
                                  member.fieldPosition ?? '–',
                                  style: TextStyle(
                                    fontFamily: sportFont,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: roleColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        CardPortrait(member: member, size: 58, special: kind),
                        const SizedBox(height: 4),
                        Text(
                          member.displayName.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: sportFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: fg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .7,
                              color: labelColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Volto della carta in tondo: il volto disegnato, la foto o il numero di maglia.
class CardPortrait extends ConsumerWidget {
  const CardPortrait({
    super.key,
    required this.member,
    required this.size,
    this.special,
  });
  final Member member;
  final double size;
  final CardSpecial? special;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (bg, fg) = switch (special) {
      CardSpecial.neroOro => (CardColors.neroOroLine, CardColors.goldText),
      CardSpecial.blu => (CardColors.blueDeep, CardColors.onBlue),
      null => (CardColors.portrait, CardColors.text),
    };
    final face = member.face;
    final photo = face == null ? memberPhoto(ref, member) : null;
    final fallback = Center(
      child: Text(
        member.shirtNumber?.toString() ??
            (member.displayName.isEmpty
                ? '?'
                : member.displayName.characters.first.toUpperCase()),
        style: TextStyle(
          fontFamily: sportFont,
          fontSize: size * .34,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: bg,
        child: face != null
            ? FaceView(face: face, size: size, crop: FaceCrop.head)
            : photo == null
            ? fallback
            : Image(
                image: photo,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Griglia di mini carte, tre per riga.
class MiniCardGrid extends StatelessWidget {
  const MiniCardGrid({super.key, required this.members, required this.onTap});
  final List<Member> members;
  final void Function(Member) onTap;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      mainAxisExtent: miniCardHeight(context),
    ),
    itemCount: members.length,
    itemBuilder: (_, i) =>
        MiniCard(member: members[i], onTap: () => onTap(members[i])),
  );
}
