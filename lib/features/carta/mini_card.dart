import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carte/special_cards_repository.dart';
import '../rosa/member.dart';
import '../volto/face_view.dart';
import 'card_stats.dart';

/// Colori (sopra, sotto, testo) di una mini carta: carta speciale o livello dell'overall,
/// come la carta grande.
(Color, Color, Color) miniCardColors(int? overall, SpecialCard? special) =>
    switch (special?.kind) {
      CardSpecial.neroOro => (
        const Color(0xFF2B2B2E),
        const Color(0xFF050505),
        const Color(0xFFF3D27A),
      ),
      CardSpecial.blu => (
        const Color(0xFF2F7BFF),
        const Color(0xFF061A5C),
        const Color(0xFFEAF2FF),
      ),
      null => switch (tierOf(overall)) {
        CardTier.vuota => (
          const Color(0xFF34343C),
          const Color(0xFF17171B),
          Colors.white,
        ),
        CardTier.bronzo => (
          const Color(0xFFD9A273),
          const Color(0xFF8A5530),
          const Color(0xFF3B2414),
        ),
        CardTier.argento => (
          const Color(0xFFF1F3F6),
          const Color(0xFF9AA1AB),
          const Color(0xFF23272E),
        ),
        CardTier.oro => (
          const Color(0xFFFBE3A0),
          const Color(0xFFC99A2E),
          const Color(0xFF3A2A08),
        ),
        CardTier.rossonera => (
          const Color(0xFFC8102E),
          const Color(0xFF0B0B0D),
          const Color(0xFFF6D77F),
        ),
      },
    };

/// Mini carta del giocatore (Rosa): volto, overall con il bonus, ruolo e nome.
class MiniCard extends ConsumerWidget {
  const MiniCard({super.key, required this.member, this.onTap});
  final Member member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final special = ref.watch(activeSpecialCardProvider(member.id));
    final (top, bottom, text) = miniCardColors(member.overall, special);
    final overall = overallWith(member.overall, special);
    final face = member.face;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: text.withValues(alpha: .45)),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: DefaultTextStyle(
          style: TextStyle(color: text, fontFamily: sportFont),
          child: Column(
            children: [
              // Overall (con il bonus) a sinistra, ruolo a destra: si rimpiccioliscono
              // se lo spazio non basta.
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            overall?.toString() ?? '–',
                            style: const TextStyle(
                              fontSize: 22,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (special != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 1),
                              child: Text(
                                '+${special.bonus}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        member.fieldPosition ?? '–',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: ClipOval(
                    child: Container(
                      width: 56,
                      height: 56,
                      color: Colors.white.withValues(alpha: .15),
                      child: face != null
                          ? FaceView(face: face, size: 56, crop: FaceCrop.head)
                          : _Initial(member: member, color: text),
                    ),
                  ),
                ),
              ),
              Text(
                member.displayName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                ),
              ),
              Text(
                special?.kind.cardLabel ?? teamsLabel(member.teams),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                  color: text.withValues(alpha: .8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initial extends ConsumerWidget {
  const _Initial({required this.member, required this.color});
  final Member member;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = memberPhoto(ref, member);
    if (photo != null) return Image(image: photo, fit: BoxFit.cover);
    return Center(
      child: Text(
        member.displayName.isEmpty
            ? '?'
            : member.displayName.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// Griglia di mini carte, tre per riga.
class MiniCardGrid extends StatelessWidget {
  const MiniCardGrid({
    super.key,
    required this.members,
    required this.onTap,
  });
  final List<Member> members;
  final void Function(Member) onTap;

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: .74,
    children: [
      for (final m in members) MiniCard(member: m, onTap: () => onTap(m)),
    ],
  );
}
