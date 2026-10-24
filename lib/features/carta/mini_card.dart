import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart' show nationalities;
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import 'card_design.dart';
import 'fut_card.dart' show CardPortraitArt;

/// Squadre scritte sotto il nome delle mini carte ("MILAN AC", "FUTURO").
String _teamsShort(Set<Team> teams) => [
  for (final t in Team.values)
    if (teams.contains(t)) t.short,
].join(' · ');

/// Proporzioni delle mini carte (le stesse della carta grande).
const miniCardAspect = 160 / 224;

/// Mini carta del giocatore (Rosa), come le carte piccole di FC: la sagoma e i colori
/// della carta grande, overall (con il bonus) e ruolo, bandiera, foto o volto, nome e
/// squadra (o il tipo di carta speciale). Colori fissi: è un oggetto di gioco.
class MiniCard extends ConsumerWidget {
  const MiniCard({super.key, required this.member, this.onTap});
  final Member member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final special = ref.watch(activeSpecialCardProvider(member.id));
    final overall = overallWith(member.overall, special);
    final kind = special?.kind;
    final design = CardDesign.of(kind, member.overall);
    final label = switch (kind) {
      CardSpecial.neroOro => 'NERO/ORO',
      CardSpecial.blu => 'BLU ELETTRICO',
      null => _teamsShort(member.teams),
    };
    final nation = member.nationality;
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
      child: MediaQuery.withNoTextScaling(
        child: GestureDetector(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: miniCardAspect,
            child: FittedBox(
              child: SizedBox(
                width: 160,
                height: 224,
                child: DefaultTextStyle(
                  style: TextStyle(fontFamily: sportFont, color: design.text),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: CardFacePainter(design, glow: kind != null),
                        ),
                      ),
                      Positioned.fill(
                        child: ClipPath(
                          clipper: const CardOutlineClipper(),
                          child: Stack(
                            children: [
                              Positioned(
                                left: 46,
                                top: 12,
                                width: 108,
                                height: 120,
                                child: CardPortraitArt(
                                  member: member,
                                  design: design,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 16,
                        width: 42,
                        child: Column(
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                overall?.toString() ?? '–',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 34,
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (nation != null &&
                                nationalities.containsKey(nation)) ...[
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(1.5),
                                child: CountryFlag.fromCountryCode(
                                  nation,
                                  theme: const ImageTheme(
                                    width: 24,
                                    height: 16,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 134,
                        height: 26,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              member.displayName.trim().toUpperCase(),
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 30,
                        right: 30,
                        top: 162,
                        child: Container(
                          height: 1,
                          color: design.line.withValues(alpha: .7),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        top: 168,
                        height: 18,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: const TextStyle(
                                fontFamily: bodyFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 196,
                        child: Icon(
                          kind == null
                              ? Icons.sports_soccer_rounded
                              : Icons.star_rounded,
                          size: 12,
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
      childAspectRatio: miniCardAspect,
    ),
    itemCount: members.length,
    itemBuilder: (_, i) =>
        MiniCard(member: members[i], onTap: () => onTap(members[i])),
  );
}
