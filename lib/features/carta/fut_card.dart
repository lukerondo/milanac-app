import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart' show memberCardPhoto, nationalities;
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../volto/face_view.dart';
import 'card_attributes.dart';
import 'card_design.dart';

export '../carte/special_cards_repository.dart' show CardSpecial;

/// La carta del giocatore come quelle di FC: overall (con il bonus della carta speciale),
/// ruolo, bandiera e stemma a sinistra; la foto scontornata (o il volto disegnato) a
/// destra; il nome e le sei statistiche sotto. Bronzo, argento, oro, rossonera (85+),
/// nero/oro della settimana o blu elettrico. Disegnata a 300×420 e scalata alla
/// larghezza disponibile; colori fissi (oggetto di gioco, uguale nei due temi) e testo
/// che non si ingrandisce con le impostazioni del telefono (la carta resta intera).
class FutCard extends ConsumerWidget {
  const FutCard({
    super.key,
    required this.member,
    this.special,
    this.bonus = 0,
    this.glow = true,
    this.previewPhoto,
  });
  final Member member;

  /// Anteprima di una foto non ancora salvata (pagina della foto della carta).
  final ImageProvider? previewPhoto;

  /// Carta speciale (nero/oro della settimana, blu elettrico) al posto di quella base.
  final CardSpecial? special;

  /// Bonus della carta speciale sull'overall e sulle statistiche (+1…+5).
  final int bonus;

  /// Bagliore attorno alle carte speciali.
  final bool glow;

  static const width = 300.0, height = 420.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final design = CardDesign.of(special, member.overall);
    final overall = member.overall == null
        ? null
        : (member.overall! + bonus).clamp(40, 99);
    final stats = statsWithBonus(member.cardStats, bonus);
    final labels = cardStatLabels(member.fieldPosition);
    final nation = member.nationality;
    final flag = nation != null && nationalities.containsKey(nation);
    final kind = switch (special) {
      CardSpecial.neroOro => 'Carta nero e oro',
      CardSpecial.blu => 'Carta blu elettrico',
      null => 'Carta',
    };
    // Una sola etichetta per chi usa il lettore di schermo.
    return Semantics(
      label: [
        '$kind: ${member.displayName}',
        ?overall?.toString(),
        ?member.fieldPosition,
        if (flag) nationalities[nation],
        if (stats != null)
          for (var i = 0; i < 6; i++) '${labels[i]} ${stats[i]}',
      ].join(', '),
      excludeSemantics: true,
      child: MediaQuery.withNoTextScaling(
        child: AspectRatio(
          aspectRatio: width / height,
          child: FittedBox(
            child: SizedBox(
              width: width,
              height: height,
              child: DefaultTextStyle(
                style: TextStyle(fontFamily: sportFont, color: design.text),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: CardFacePainter(design, glow: glow),
                      ),
                    ),
                    // Foto o volto, ritagliati con la sagoma della carta.
                    Positioned.fill(
                      child: ClipPath(
                        clipper: const CardOutlineClipper(),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 92,
                              top: 24,
                              width: 196,
                              height: 226,
                              child: CardPortraitArt(
                                member: member,
                                design: design,
                                photoOverride: previewPhoto,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Overall, ruolo, bandiera e stemma.
                    Positioned(
                      left: 22,
                      top: 30,
                      width: 76,
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              overall?.toString() ?? '??',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 60,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              member.fieldPosition ?? '–',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (bonus > 0 && overall != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: design.text.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+$bonus',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          CardRule(color: design.line),
                          if (flag) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: CountryFlag.fromCountryCode(
                                nation,
                                theme: const ImageTheme(width: 38, height: 26),
                              ),
                            ),
                            const SizedBox(height: 8),
                            CardRule(color: design.line),
                          ],
                          const SizedBox(height: 8),
                          Image.asset(
                            'assets/images/stemma_256.png',
                            width: 40,
                            height: 40,
                          ),
                        ],
                      ),
                    ),
                    // Nome sulla carta.
                    Positioned(
                      left: 22,
                      right: 22,
                      top: 250,
                      height: 38,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            member.displayName.trim().toUpperCase(),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .6,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 46,
                      right: 46,
                      top: 292,
                      child: Container(
                        height: 1.4,
                        color: design.line.withValues(alpha: .7),
                      ),
                    ),
                    // Le sei statistiche, in due colonne.
                    Positioned(
                      left: 44,
                      right: 44,
                      top: 300,
                      height: 90,
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatColumn(
                              values: stats?.sublist(0, 3),
                              labels: labels.sublist(0, 3),
                            ),
                          ),
                          Container(
                            width: 1.4,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: design.line.withValues(alpha: .7),
                          ),
                          Expanded(
                            child: _StatColumn(
                              values: stats?.sublist(3),
                              labels: labels.sublist(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 392,
                      child: Icon(
                        special == null
                            ? Icons.sports_soccer_rounded
                            : Icons.star_rounded,
                        size: 18,
                        color: design.line,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tre statistiche una sotto l'altra: "88 TIR" (numero in grassetto, sigla leggera).
class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.values, required this.labels});
  final List<int>? values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (var i = 0; i < 3; i++)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Se un font è più largo il testo si rimpicciolisce, non va a capo.
            SizedBox(
              width: 34,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  values?[i].toString() ?? '--',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 40,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  labels[i],
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
    ],
  );
}

/// Il ritratto sulla carta: la foto caricata dal giocatore (meglio se scontornata),
/// sfumata in basso nel fondo della carta; senza foto il volto disegnato; senza volto
/// la sagoma, come le carte di FC ancora da completare.
class CardPortraitArt extends ConsumerWidget {
  const CardPortraitArt({
    super.key,
    required this.member,
    required this.design,
    this.photoOverride,
  });
  final Member member;
  final CardDesign design;

  /// Una foto da mostrare al posto di quella salvata (anteprima).
  final ImageProvider? photoOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = photoOverride ?? memberCardPhoto(ref, member);
    final face = member.face;
    final Widget art;
    if (photo != null) {
      art = Image(
        image: photo,
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(face),
      );
    } else {
      art = _fallback(face);
    }
    // In basso la foto sfuma nel fondo, come le carte vere.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, .80, 1],
      ).createShader(rect),
      child: art,
    );
  }

  Widget _fallback(Object? face) => face == null
      ? Align(
          alignment: Alignment.bottomCenter,
          child: Icon(
            Icons.person_rounded,
            size: 210,
            color: Colors.black.withValues(alpha: .22),
          ),
        )
      : Align(
          alignment: Alignment.bottomCenter,
          child: FaceView(face: member.face!, size: 206),
        );
}

/// Retro della carta (nel walkout, mentre gira): nero e oro con lo stemma.
class FutCardBack extends StatelessWidget {
  const FutCardBack({super.key});

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: FutCard.width / FutCard.height,
    child: CustomPaint(
      painter: const CardFacePainter(CardDesign.neroOro, glow: false),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: .45,
          child: Image.asset('assets/images/stemma_256.png'),
        ),
      ),
    ),
  );
}
