import 'package:flutter/material.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart' show flagEmoji;
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../risultati/result_ui.dart' show ClubCrest;
import 'archetypes.dart';
import 'card_colors.dart';
import 'card_stats.dart';
import 'mini_card.dart' show CardPortrait;
import 'playstyle_ui.dart';

export '../carte/special_cards_repository.dart' show CardSpecial;

/// Colori di una carta grande: sfumatura, bordo, scritte, riga dei dati.
class _Look {
  const _Look(this.top, this.bottom, this.border, this.text, this.info);
  final Color top, bottom, border, text, info;

  static _Look of(CardSpecial? special, int? overall) => switch (special) {
    CardSpecial.neroOro => const _Look(
      CardColors.neroOroLight,
      MilanacColors.black,
      CardColors.gold,
      CardColors.goldText,
      CardColors.neroOroInfo,
    ),
    CardSpecial.blu => const _Look(
      CardColors.blue,
      CardColors.blueDeep,
      CardColors.blueRing,
      CardColors.onBlue,
      CardColors.onBlueMuted,
    ),
    null => _Look(
      CardColors.surfaceHigh,
      MilanacColors.black,
      CardColors.tier(tierOf(overall)),
      CardColors.text,
      CardColors.textMuted,
    ),
  };
}

/// Sigla breve della piattaforma sulla carta.
String _platform(GamePlatform p) => switch (p) {
  GamePlatform.ps5 => 'PS5',
  GamePlatform.xbox => 'XBOX',
  GamePlatform.pc => 'PC',
};

/// La carta del giocatore come nelle tavole del profilo e del walkout: overall con il
/// bonus, ruolo, stemma, volto, nome, stile di gioco e dati (piattaforma, numero,
/// squadre). Nero/oro, blu elettrico o normale con il colore del livello sul bordo.
/// Disegnata a 210×300 e scalata alla larghezza disponibile; colori fissi (oggetto
/// di gioco, uguale nei due temi).
class FutCard extends StatelessWidget {
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

  /// Bonus della carta speciale sull'overall (+1…+5).
  final int bonus;

  /// Alone sottile attorno alla carta.
  final bool glow;

  static const width = 210.0, height = 300.0;

  @override
  Widget build(BuildContext context) {
    final look = _Look.of(special, member.overall);
    final overall = member.overall == null
        ? null
        : (member.overall! + bonus).clamp(40, 99);
    final info = [
      if (member.platform != null) _platform(member.platform!),
      if (member.shirtNumber != null) 'N. ${member.shirtNumber}',
      for (final t in Team.values)
        if (member.teams.contains(t)) t.short,
    ].join(' · ');
    final style = member.playStyle?.trim() ?? '';
    final archetype = archetypeOf(style);
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
    // Una sola etichetta per chi usa il lettore di schermo.
    return Semantics(
      label: [
        '${kind[0].toUpperCase()}${kind.substring(1)}: ${member.displayName}',
        ?overall?.toString(),
        ?member.fieldPosition,
        if (style.isNotEmpty) style,
        if (plus.isNotEmpty)
          'PlayStyle+: ${plus.map((c) => c.style.name).join(', ')}',
        if (info.isNotEmpty) info,
      ].join(', '),
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: width / height,
        child: FittedBox(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: look.border, width: 2),
              gradient: LinearGradient(
                begin: const Alignment(-.35, -1),
                end: const Alignment(.35, 1),
                colors: [look.top, look.bottom],
                stops: const [0, .7],
              ),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: look.border.withValues(alpha: .12),
                        spreadRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: DefaultTextStyle(
              style: TextStyle(fontFamily: sportFont, color: look.text),
              child: Stack(
                children: [
                  // Overall, bonus e ruolo in alto a sinistra.
                  Positioned(
                    left: 16,
                    top: 14,
                    child: Column(
                      children: [
                        Text(
                          overall?.toString() ?? '??',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        if (bonus > 0 && overall != null)
                          Text(
                            '+$bonus',
                            style: const TextStyle(
                              fontFamily: bodyFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          member.fieldPosition ?? '–',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                        // La bandiera, se il giocatore ha indicato la nazionalità.
                        if (member.nationality != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            flagEmoji(member.nationality!),
                            style: const TextStyle(fontSize: 20, height: 1),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: const ClubCrest(size: 40),
                  ),
                  // I PlayStyle+ sotto lo stemma, nei rombi d'oro.
                  if (plus.isNotEmpty)
                    Positioned(
                      right: 15,
                      top: 64,
                      child: Column(
                        children: [
                          for (final c in plus) ...[
                            PlayStyleBadge(
                              style: c.style,
                              plus: true,
                              size: 30,
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),
                    ),
                  // Volto.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 88,
                    child: Center(
                      child: CardPortrait(
                        member: member,
                        size: 112,
                        special: special,
                      ),
                    ),
                  ),
                  // Nome, stile di gioco e dati.
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 206,
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            member.displayName.trim().toUpperCase(),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (style.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (archetype != null) ...[
                                Icon(
                                  archetype.icon,
                                  size: 13,
                                  color: look.text,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  style.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.6,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        if (info.isNotEmpty)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              info,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: look.info,
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

/// Retro della carta (nel walkout, mentre gira): nero e oro con lo stemma.
class FutCardBack extends StatelessWidget {
  const FutCardBack({super.key});

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: FutCard.width / FutCard.height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22 * 260 / FutCard.width),
        border: Border.all(color: CardColors.gold, width: 2),
        gradient: const LinearGradient(
          begin: Alignment(-.35, -1),
          end: Alignment(.35, 1),
          colors: [CardColors.neroOroLight, MilanacColors.black],
          stops: [0, .7],
        ),
      ),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: .45,
          child: Image.asset('assets/images/stemma_256.png'),
        ),
      ),
    ),
  );
}
