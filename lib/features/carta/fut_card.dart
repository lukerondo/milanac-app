import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../../shared/silhouette.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import 'archetypes.dart';
import 'fut_card_skin.dart';
import 'fut_stats.dart';
import 'playstyle_ui.dart';

export '../carte/special_cards_repository.dart' show CardSpecial;

/// La carta del giocatore come un oggetto di FUT (FC 24–26): overall, ruolo e PlayStyle+
/// in alto a sinistra, la foto caricata dal giocatore, il nome, le sei statistiche in
/// riga e in fondo bandiera e stemma. Bronzo, argento e oro secondo l'overall,
/// rossonera sopra 85, nero/oro e blu elettrico per le carte speciali (il bonus sale
/// sull'overall e sulle statistiche, come le carte in-form). Disegnata a 210×300 e
/// scalata alla larghezza disponibile; colori fissi (uguali nei due temi).
class FutCard extends ConsumerWidget {
  const FutCard({
    super.key,
    required this.member,
    this.special,
    this.bonus = 0,
    this.glow = true,
  });
  final Member member;

  /// Carta speciale (nero/oro della settimana, blu elettrico) al posto di quella base.
  final CardSpecial? special;

  /// Bonus della carta speciale (+1…+5) su overall e statistiche.
  final int bonus;

  /// Alone sottile attorno alla carta.
  final bool glow;

  static const width = 210.0, height = 300.0;

  /// Dove sta la foto sulla carta (4:5, come l'inquadratura scelta dal giocatore).
  static const photoRect = Rect.fromLTWH(46, 0, 160, 200);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = CardSkin.of(special, member.overall);
    final overall = member.overall == null
        ? null
        : (member.overall! + bonus).clamp(40, 99);
    final stats = [
      for (final s in FutStat.forPosition(member.fieldPosition))
        (s, _boosted(member.futStats[s])),
    ];
    // Sulla carta i PlayStyle+ (al massimo due), come in FC; gli altri nel profilo.
    final plus = [
      for (final c in chosenPlayStyles(member.playStyles))
        if (c.plus) c,
    ];
    final kind = switch (special) {
      CardSpecial.neroOro => 'carta nero e oro',
      CardSpecial.blu => 'carta blu elettrico',
      null => 'carta',
    };
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    // Una sola etichetta per chi usa il lettore di schermo.
    return Semantics(
      label: [
        '${kind[0].toUpperCase()}${kind.substring(1)}: ${member.displayName}',
        ?overall?.toString(),
        ?member.fieldPosition,
        for (final (s, v) in stats)
          if (v != null) '${s.label} $v',
        if (plus.isNotEmpty)
          'PlayStyle+: ${plus.map((c) => c.style.name).join(', ')}',
        if (member.avatarPath == null) 'senza foto',
      ].join(', '),
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: width / height,
        child: FittedBox(
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              // L'alone segue la forma della carta (non un rettangolo).
              painter: glow ? _GlowPainter(skin.rim) : null,
              child: CustomPaint(
                painter: CardSkinPainter(skin),
                foregroundPainter: _RimPainter(skin),
                child: DefaultTextStyle(
                  style: TextStyle(fontFamily: sportFont, color: skin.text),
                  child: Stack(
                    children: [
                      // La foto (o la sagoma) dentro la forma della carta.
                      Positioned.fill(
                        child: ClipPath(
                          clipper: const FutCardClipper(),
                          child: Stack(
                            children: [
                              Positioned.fromRect(
                                rect: photoRect,
                                child: CardPhoto(
                                  member: member,
                                  silhouette: skin.text,
                                  cacheWidth: (photoRect.width * dpr * 2)
                                      .ceil(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Overall, bonus, ruolo e PlayStyle+ in colonna a sinistra.
                      Positioned(
                        left: 18,
                        top: 30,
                        width: 54,
                        child: Column(
                          children: [
                            Text(
                              overall?.toString() ?? '??',
                              style: const TextStyle(
                                fontSize: 46,
                                fontWeight: FontWeight.w700,
                                height: .95,
                                letterSpacing: -1,
                              ),
                            ),
                            if (bonus > 0 && overall != null)
                              Text(
                                '+$bonus',
                                style: const TextStyle(
                                  fontFamily: bodyFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              member.fieldPosition ?? '–',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w500,
                                height: 1,
                              ),
                            ),
                            for (final c in plus) ...[
                              const SizedBox(height: 7),
                              PlayStyleBadge(
                                style: c.style,
                                plus: true,
                                size: 26,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Nome.
                      Positioned(
                        left: 18,
                        right: 18,
                        top: 196,
                        height: 24,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              member.displayName.trim().toUpperCase(),
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .4,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 40,
                        right: 40,
                        top: 221,
                        child: Container(
                          height: .8,
                          color: skin.text.withValues(alpha: .35),
                        ),
                      ),
                      // Le sei statistiche: sigla sopra, valore sotto.
                      Positioned(
                        left: 19,
                        right: 19,
                        top: 224,
                        child: Row(
                          children: [
                            for (final (s, v) in stats)
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      s.short,
                                      style: TextStyle(
                                        fontFamily: bodyFont,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .4,
                                        height: 1.2,
                                        color: skin.label,
                                      ),
                                    ),
                                    Text(
                                      v?.toString() ?? '–',
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                        height: 1.05,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Bandiera (se indicata) e stemma del club.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 258,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (member.nationality != null) ...[
                              Text(
                                flagEmoji(member.nationality!),
                                style: const TextStyle(fontSize: 15, height: 1),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Image.asset(
                              'assets/images/stemma_256.png',
                              width: 20,
                              height: 20,
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
        ),
      ),
    );
  }

  int? _boosted(int? v) =>
      v == null ? null : (v + bonus).clamp(FutStats.min, FutStats.max);
}

/// Alone della carta, sulla sua forma.
class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    futCardPath(size),
    Paint()
      ..color = color.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 9),
  );

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color;
}

/// Il bordo ripassato sopra la foto, che così non esce dalla carta.
class _RimPainter extends CustomPainter {
  const _RimPainter(this.skin);
  final CardSkin skin;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    futCardPath(size),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = skin.rim,
  );

  @override
  bool shouldRepaint(_RimPainter old) => old.skin != skin;
}

/// Il ritratto della carta: solo la foto caricata dal giocatore, che sfuma a sinistra e
/// in basso dentro la carta come i giocatori di FUT; senza foto la sagoma grigia.
class CardPhoto extends ConsumerWidget {
  const CardPhoto({
    super.key,
    required this.member,
    required this.silhouette,
    this.cacheWidth,
  });
  final Member member;

  /// Colore della sagoma (le scritte della carta, molto trasparenti).
  final Color silhouette;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = CustomPaint(
      painter: SilhouettePainter(silhouette.withValues(alpha: .26), inset: .1),
      size: Size.infinite,
    );
    final photo = memberPhoto(ref, member, cacheWidth: cacheWidth);
    if (photo == null) return shape;
    Shader fade(Rect r, Alignment begin, Alignment end, List<double> stops) =>
        LinearGradient(
          begin: begin,
          end: end,
          colors: const [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: stops,
        ).createShader(r);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => fade(
        r,
        Alignment.topCenter,
        Alignment.bottomCenter,
        const [0, 0, .74, 1],
      ),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => fade(
          r,
          Alignment.centerLeft,
          Alignment.centerRight,
          const [0, .16, .93, 1],
        ),
        child: Image(
          image: photo,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -.3),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => shape,
        ),
      ),
    );
  }
}

/// Retro della carta (nel walkout, mentre gira): nero e oro con lo stemma.
class FutCardBack extends StatelessWidget {
  const FutCardBack({super.key});

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: FutCard.width / FutCard.height,
    child: CustomPaint(
      painter: const CardSkinPainter(CardSkin.neroOro),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: .45,
          child: Image.asset('assets/images/stemma_256.png'),
        ),
      ),
    ),
  );
}
