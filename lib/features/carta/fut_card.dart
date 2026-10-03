import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/teams.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../rosa/member.dart';
import 'card_stats.dart';

/// Versioni speciali della carta, come le carte "in forma" di FUT.
enum CardSpecial {
  motm('UOMO PARTITA'),
  totw('SQUADRA DELLA SETTIMANA');

  const CardSpecial(this.label);
  final String label;
}

/// Carta in stile FUT del giocatore. Disegnata a 300×428 e scalata alla larghezza disponibile.
class FutCard extends StatelessWidget {
  const FutCard({
    super.key,
    required this.member,
    required this.stats,
    this.special,
    this.badges = const [],
  });
  final Member member;
  final CardStats stats;

  /// Carta speciale (Uomo partita, Squadra della settimana) al posto di quella base.
  final CardSpecial? special;

  /// Badge dei traguardi da mostrare sulla carta (icona, colore), al massimo 3.
  final List<(IconData, Color)> badges;

  static const _w = 300.0, _h = 428.0;

  @override
  Widget build(BuildContext context) {
    final palette = switch (special) {
      CardSpecial.motm => _Palette.motm,
      CardSpecial.totw => _Palette.totw,
      null => _Palette.of(tierOf(member.overall)),
    };
    return AspectRatio(
      aspectRatio: _w / _h,
      child: FittedBox(
        child: SizedBox(
          width: _w,
          height: _h,
          child: CustomPaint(
            painter: _CardPainter(palette),
            child: DefaultTextStyle(
              style: TextStyle(color: palette.text, fontFamily: sportFont),
              child: _CardContent(
                member: member,
                stats: stats,
                palette: palette,
                special: special,
                badges: badges,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Palette {
  const _Palette(this.top, this.bottom, this.text, this.line);
  final Color top, bottom, text, line;

  /// Uomo partita: nera e oro.
  static const motm = _Palette(
    Color(0xFF2B2B2E),
    Color(0xFF050505),
    Color(0xFFF3D27A),
    Color(0xAAF3D27A),
  );

  /// Squadra della settimana: nera con riflessi rossi e oro.
  static const totw = _Palette(
    Color(0xFF3A0A12),
    Color(0xFF050505),
    Color(0xFFF6D77F),
    Color(0xAAF6D77F),
  );

  static _Palette of(CardTier tier) => switch (tier) {
    CardTier.vuota => const _Palette(
      Color(0xFF34343C),
      Color(0xFF17171B),
      Color(0xFFE5E5E5),
      Color(0x55FFFFFF),
    ),
    CardTier.bronzo => const _Palette(
      Color(0xFFD9A273),
      Color(0xFF8A5530),
      Color(0xFF3B2414),
      Color(0x663B2414),
    ),
    CardTier.argento => const _Palette(
      Color(0xFFF1F3F6),
      Color(0xFF9AA1AB),
      Color(0xFF23272E),
      Color(0x6623272E),
    ),
    CardTier.oro => const _Palette(
      Color(0xFFFBE3A0),
      Color(0xFFC99A2E),
      Color(0xFF3A2A08),
      Color(0x663A2A08),
    ),
    CardTier.rossonera => const _Palette(
      Color(0xFFC8102E),
      Color(0xFF0B0B0D),
      Color(0xFFF6D77F),
      Color(0x88F6D77F),
    ),
  };
}

/// Sagoma a scudo con angoli tagliati, come le carte FUT.
Path cardShape(Size s) {
  final w = s.width, h = s.height;
  return Path()
    ..moveTo(w * .16, h * .025)
    ..quadraticBezierTo(w * .5, -h * .015, w * .84, h * .025)
    ..lineTo(w * .97, h * .09)
    ..quadraticBezierTo(w * .99, h * .1, w * .99, h * .13)
    ..lineTo(w * .99, h * .84)
    ..quadraticBezierTo(w * .99, h * .87, w * .95, h * .885)
    ..quadraticBezierTo(w * .7, h * .955, w * .5, h * .995)
    ..quadraticBezierTo(w * .3, h * .955, w * .05, h * .885)
    ..quadraticBezierTo(w * .01, h * .87, w * .01, h * .84)
    ..lineTo(w * .01, h * .13)
    ..quadraticBezierTo(w * .01, h * .1, w * .03, h * .09)
    ..close();
}

class _CardPainter extends CustomPainter {
  const _CardPainter(this.p);
  final _Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = cardShape(size);
    canvas.drawShadow(shape, Colors.black, 10, false);
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.top, p.bottom],
        ).createShader(Offset.zero & size),
    );
    // Riflesso diagonale.
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .55, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * .35)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .10),
    );
    canvas.restore();
    // Bordo interno.
    final inner = cardShape(size * .94)
        .shift(Offset(size.width * .03, size.height * .03));
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = p.line,
    );
  }

  @override
  bool shouldRepaint(_CardPainter old) => old.p != p;
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.member,
    required this.stats,
    required this.palette,
    this.special,
    this.badges = const [],
  });
  final Member member;
  final CardStats stats;
  final _Palette palette;
  final CardSpecial? special;
  final List<(IconData, Color)> badges;

  @override
  Widget build(BuildContext context) {
    final surname = member.displayName.trim().split(' ').last.toUpperCase();
    String pct(int? v) => v == null ? '–' : '$v';
    final left = [
      (pct(stats.presence), 'PRE'),
      (pct(stats.punctuality), 'PUN'),
      ('${stats.nights}', 'SER'),
    ];
    final right = [
      ('${stats.goals}', 'GOL'),
      ('${stats.months}', 'ANZ'),
      (pct(stats.winRate), 'VIT'),
    ];

    return Stack(
      children: [
        if (special != null)
          Positioned(
            top: 22,
            left: 60,
            right: 60,
            child: Text(
              special!.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
          ),
        // Overall, ruolo, stemma, piattaforma.
        Positioned(
          left: 34,
          top: 46,
          child: Column(
            children: [
              Text(
                member.overall?.toString() ?? '??',
                style: const TextStyle(
                  fontSize: 50,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                member.fieldPosition ?? '–',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (member.nationality != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    flagEmoji(member.nationality!),
                    style: const TextStyle(fontSize: 26, height: 1.1),
                  ),
                ),
              Image.asset('assets/images/stemma_milano_fc.png', height: 38),
              const SizedBox(height: 6),
              if (member.platform != null)
                Text(
                  member.platform!.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
            ],
          ),
        ),
        // Foto o sagoma con il numero di maglia.
        Positioned(
          right: 26,
          top: 40,
          width: 170,
          height: 170,
          child: _Portrait(member: member, color: palette.text),
        ),
        // Nome.
        Positioned(
          left: 20,
          right: 20,
          top: 214,
          child: Column(
            children: [
              Text(
                surname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                ),
              ),
              if (member.playStyle != null && member.playStyle!.isNotEmpty)
                Text(
                  member.playStyle!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 6),
                height: 1.2,
                color: palette.line,
              ),
            ],
          ),
        ),
        // Statistiche.
        Positioned(
          left: 44,
          right: 44,
          top: 282,
          child: Row(
            children: [
              Expanded(child: _StatColumn(left)),
              Container(width: 1.2, height: 84, color: palette.line),
              Expanded(child: _StatColumn(right)),
            ],
          ),
        ),
        // Badge dei traguardi più rari.
        if (badges.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (icon, color) in badges)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(color: palette.text, width: 1),
                    ),
                    child: Icon(icon, size: 12, color: Colors.white),
                  ),
              ],
            ),
          ),
        // Squadre e numero di maglia.
        Positioned(
          left: 60,
          right: 60,
          bottom: 30,
          child: Text(
            [
              teamsLabel(member.teams),
              if (member.shirtNumber != null) '#${member.shirtNumber}',
            ].join('  ·  '),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn(this.values);
  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (value, label) in values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 40,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Portrait extends ConsumerWidget {
  const _Portrait({required this.member, required this.color});
  final Member member;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = memberPhoto(ref, member);
    final silhouette = Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.person_rounded,
          size: 170,
          color: color.withValues(alpha: .22),
        ),
        Positioned(
          bottom: 30,
          child: Text(
            member.shirtNumber?.toString() ?? '',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: color.withValues(alpha: .55),
            ),
          ),
        ),
      ],
    );
    if (photo == null) return silhouette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(85),
      child: Image(
        image: photo,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => silhouette,
      ),
    );
  }
}

/// Spiegazione delle sigle sotto la carta.
const cardStatLegend = {
  'PRE': 'presenze negli ultimi 60 giorni (%)',
  'PUN': 'puntualità: presenze senza ritardo (%)',
  'SER': 'serate presenti negli ultimi 60 giorni',
  'GOL': 'gol segnati nelle partite registrate',
  'ANZ': 'mesi nel club',
  'VIT': 'vittorie delle sue squadre (%)',
};

/// Badge di squadra usati sotto la carta.
List<Widget> teamBadges(Set<Team> teams) => [
  for (final t in Team.values)
    if (teams.contains(t)) TeamBadge(t),
];
