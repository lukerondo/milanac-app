import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../../shared/silhouette.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import 'card_colors.dart';
import 'card_stats.dart';
import 'fut_card.dart' show CardPhoto;
import 'fut_card_skin.dart';

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

/// Etichetta del volo della carta dalla Rosa (mini carta) alla carta grande.
Object cardHeroTag(String memberId) => 'carta-$memberId';

/// Mini carta del giocatore (Rosa): la stessa carta FUT in piccolo, come nella rosa di
/// FC. Overall con il bonus, ruolo, foto (o sagoma), nome e squadre o tipo di carta
/// speciale. Disegnata a 140×200 e scalata alla cella; colori fissi.
class MiniCard extends ConsumerWidget {
  const MiniCard({super.key, required this.member, this.onTap});
  final Member member;
  final VoidCallback? onTap;

  static const width = 140.0, height = 200.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final special = ref.watch(activeSpecialCardProvider(member.id));
    final overall = overallWith(member.overall, special);
    final kind = special?.kind;
    final skin = CardSkin.of(kind, member.overall);
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
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
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
          child: GestureDetector(
            onTap: onTap,
            // Oggetto disegnato a misura fissa e scalato: il testo grande del telefono non
            // deve spostare overall, ruolo e statistiche sulla foto.
            child: MediaQuery.withNoTextScaling(
              child: AspectRatio(
                aspectRatio: width / height,
                child: FittedBox(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: CustomPaint(
                      painter: CardSkinPainter(skin, rimWidth: 1.6),
                      child: DefaultTextStyle(
                        style: TextStyle(
                          fontFamily: sportFont,
                          color: skin.text,
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipPath(
                                clipper: const FutCardClipper(),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: 36,
                                      top: 9,
                                      width: 100,
                                      height: 125,
                                      child: CardPhoto(
                                        member: member,
                                        silhouette: skin.text,
                                        cacheWidth: (100 * dpr * 1.5).ceil(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Overall (con il bonus) e ruolo in alto a sinistra.
                            Positioned(
                              left: 10,
                              top: 20,
                              width: 40,
                              child: Column(
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      overall?.toString() ?? '–',
                                      style: const TextStyle(
                                        fontSize: 31,
                                        fontWeight: FontWeight.w700,
                                        height: 1,
                                        letterSpacing: -.5,
                                      ),
                                    ),
                                  ),
                                  if (special != null)
                                    Text(
                                      '+${special.bonus}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                      ),
                                    ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      member.fieldPosition ?? '–',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              top: 132,
                              height: 22,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    member.displayName.toUpperCase(),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              top: 156,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: bodyFont,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .7,
                                    color: skin.label,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 173,
                              child: Center(
                                child: Image.asset(
                                  'assets/images/stemma_256.png',
                                  width: 15,
                                  height: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ritratto tondo per le carte piccole (formazione in campo): la foto caricata dal
/// giocatore o la sagoma grigia.
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
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final photo = memberPhoto(ref, member, cacheWidth: (size * dpr).ceil());
    final fallback = PlayerSilhouette(background: bg, color: fg);
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: photo == null
            ? fallback
            : Image(
                image: photo,
                fit: BoxFit.cover,
                alignment: photoAlignment,
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
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 10,
      childAspectRatio: MiniCard.width / MiniCard.height,
    ),
    itemCount: members.length,
    itemBuilder: (_, i) =>
        MiniCard(member: members[i], onTap: () => onTap(members[i])),
  );
}
