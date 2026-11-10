import 'dart:ui' as ui;

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

/// La carta del giocatore come un oggetto da collezione: cornice di metallo spazzolato,
/// overall, ruolo e PlayStyle+ in alto a sinistra, il giocatore al centro (la sua foto
/// ritagliata dallo sfondo, o l'omino del club) tagliato dalla targa bassa con il nome,
/// le sei statistiche in riga e in fondo bandiera e stemma. Bronzo, argento e oro
/// secondo l'overall, rossonera sopra 85, nero/oro e blu elettrico per le carte speciali
/// (il bonus sale sull'overall e sulle statistiche, come le carte in-form). Disegnata a
/// 210×300 e scalata alla larghezza disponibile; colori fissi (uguali nei due temi).
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
                // L'alone segue la forma della carta (non un rettangolo).
                painter: glow ? _GlowPainter(skin.rim) : null,
                child: CardFrame(
                  skin: skin,
                  // Il giocatore (foto o omino) dentro la carta, dietro la targa.
                  figure: CardPhoto(
                    member: member,
                    cacheWidth: (photoRect.width * dpr * 2).ceil(),
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(fontFamily: sportFont, color: skin.text),
                    child: Stack(
                      children: [
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
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1,
                                  ),
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

/// Il giocatore sulla carta, dietro la targa: la sua foto ritagliata dallo sfondo
/// (quando il server l'ha preparata), altrimenti la foto intera che sfuma dentro la
/// carta; senza foto l'omino del club. Occupa tutta la carta: le posizioni sono in
/// frazioni, così vale per la carta grande e per la mini.
class CardPhoto extends ConsumerWidget {
  const CardPhoto({
    super.key,
    required this.member,
    this.cacheWidth,
    this.shadow = true,
  });
  final Member member;
  final int? cacheWidth;

  /// Ombra morbida dietro la figura (sulla carta grande).
  final bool shadow;

  /// Dove stanno l'omino e la foto (frazioni della carta). La foto è 4:5, come
  /// l'inquadratura scelta dal giocatore; la targa ne copre il fondo.
  static const ominoBox = Rect.fromLTWH(.26, .088, .754, .528);
  static const photoBox = Rect.fromLTWH(46 / 210, 0, 160 / 210, 200 / 300);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cutout = photoOf(
      ref,
      member.avatarCutoutPath,
      cacheWidth: cacheWidth,
    );
    final path = member.avatarPath;
    final loading = path == null ? null : ref.watch(photoBytesProvider(path));
    final photo = cutout == null
        ? memberPhoto(ref, member, cacheWidth: cacheWidth)
        : null;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        Widget at(Rect f, Widget child) => Positioned(
          left: f.left * size.width,
          top: f.top * size.height,
          width: f.width * size.width,
          height: f.height * size.height,
          child: child,
        );
        final omino = at(ominoBox, _shadowed(const PlayerOmino(), size));
        final Widget figure;
        if (cutout != null) {
          figure = at(photoBox, _shadowed(_Cutout(image: cutout), size));
        } else if (photo != null) {
          figure = at(
            photoBox,
            _FadedPhoto(image: photo, fallback: const PlayerOmino()),
          );
        } else if (loading != null && loading.isLoading && !loading.hasValue) {
          // La foto c'è ma sta arrivando: niente omino che lampeggia prima di lei.
          figure = const SizedBox.shrink();
        } else {
          figure = omino;
        }
        return Stack(children: [figure]);
      },
    );
  }

  /// La figura con la sua ombra: la stessa immagine, nera e sfocata, appena più in basso.
  Widget _shadowed(Widget figure, Size card) {
    if (!shadow) return figure;
    final blur = card.width * .017;
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.translate(
          offset: Offset(0, card.width * .017),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.decal,
            ),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x73000000),
                BlendMode.srcIn,
              ),
              child: figure,
            ),
          ),
        ),
        figure,
      ],
    );
  }
}

Shader _fade(
  Rect r,
  Alignment begin,
  Alignment end,
  List<Color> colors,
  List<double> stops,
) => LinearGradient(
  begin: begin,
  end: end,
  colors: colors,
  stops: stops,
).createShader(r);

/// La foto senza sfondo: la figura si scioglie nella carta verso il basso (la targa la
/// taglia poco dopo) e a sinistra, dove le spalle passerebbero sotto overall e ruolo.
class _Cutout extends StatelessWidget {
  const _Cutout({required this.image});
  final ImageProvider image;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (r) => _fade(
      r,
      Alignment.topCenter,
      Alignment.bottomCenter,
      const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x33FFFFFF)],
      const [0, .7, .93],
    ),
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => _fade(
        r,
        Alignment.centerLeft,
        Alignment.centerRight,
        const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
        const [0, .15, 1],
      ),
      child: Image(
        image: image,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -.3),
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}

/// La foto intera (il ritaglio non c'è ancora): sfuma a sinistra e in basso dentro la
/// carta.
class _FadedPhoto extends StatelessWidget {
  const _FadedPhoto({required this.image, required this.fallback});
  final ImageProvider image;
  final Widget fallback;

  static const _colors = [
    Color(0x00FFFFFF),
    Color(0xFFFFFFFF),
    Color(0xFFFFFFFF),
    Color(0x00FFFFFF),
  ];

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (r) => _fade(
      r,
      Alignment.topCenter,
      Alignment.bottomCenter,
      _colors,
      const [0, 0, .74, 1],
    ),
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => _fade(
        r,
        Alignment.centerLeft,
        Alignment.centerRight,
        _colors,
        const [0, .16, .93, 1],
      ),
      child: Image(
        image: image,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -.3),
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    ),
  );
}

/// Retro della carta (nel walkout, mentre gira): nero e oro con lo stemma.
class FutCardBack extends StatelessWidget {
  const FutCardBack({super.key});

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: FutCard.width / FutCard.height,
    child: CardFrame(
      skin: CardSkin.neroOro,
      child: Align(
        alignment: const Alignment(0, -.3),
        child: FractionallySizedBox(
          widthFactor: .45,
          child: Image.asset('assets/images/stemma_256.png'),
        ),
      ),
    ),
  );
}
