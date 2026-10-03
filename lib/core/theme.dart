import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Palette rossonera del club.
class MilanacColors {
  static const red = Color(0xFFC8102E);
  static const redDark = Color(0xFF8E0B20);
  static const gold = Color(0xFFD4AF37);
  static const black = Color(0xFF0B0B0D);
  static const surface = Color(0xFF17171B);
  static const surfaceHigh = Color(0xFF222228);
}

/// Font sportivo condensato per titoli, numeri e carte (come nell'interfaccia di FC).
const sportFont = 'BarlowCondensed';

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: MilanacColors.red,
        brightness: Brightness.dark,
      ).copyWith(
        primary: MilanacColors.red,
        secondary: MilanacColors.gold,
        surface: MilanacColors.surface,
        surfaceContainerHighest: MilanacColors.surfaceHigh,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
  );
  TextStyle? sport(TextStyle? t, {FontWeight weight = FontWeight.w800}) =>
      t?.copyWith(fontFamily: sportFont, fontWeight: weight, letterSpacing: .3);

  return base.copyWith(
    scaffoldBackgroundColor: MilanacColors.black,
    textTheme: base.textTheme.copyWith(
      displayLarge: sport(base.textTheme.displayLarge, weight: FontWeight.w900),
      displayMedium: sport(
        base.textTheme.displayMedium,
        weight: FontWeight.w900,
      ),
      displaySmall: sport(base.textTheme.displaySmall, weight: FontWeight.w900),
      headlineLarge: sport(
        base.textTheme.headlineLarge,
        weight: FontWeight.w900,
      ),
      headlineMedium: sport(
        base.textTheme.headlineMedium,
        weight: FontWeight.w900,
      ),
      headlineSmall: sport(
        base.textTheme.headlineSmall,
        weight: FontWeight.w900,
      ),
      titleLarge: sport(base.textTheme.titleLarge),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MilanacColors.black,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: sportFont,
        fontSize: 23,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: Colors.white,
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: MilanacColors.black),
    // Card "a vetro": semitrasparenti sullo sfondo da stadio, bordo chiaro sottile.
    cardTheme: CardThemeData(
      color: const Color(0xC81A1A1F),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x26FFFFFF)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MilanacColors.red,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: sportFont,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    // Transizioni morbide tra le pagine.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Sfondo delle sezioni: notte allo stadio, con luci dei riflettori e linee del campo.
class StadiumBackground extends StatelessWidget {
  const StadiumBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1A0609), MilanacColors.black, Color(0xFF07070A)],
        stops: [0, .45, 1],
      ),
    ),
    child: CustomPaint(painter: const _FloodlightsPainter(), child: child),
  );
}

class _FloodlightsPainter extends CustomPainter {
  const _FloodlightsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, double r, Color color) => canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [color, Colors.transparent])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Riflettori in alto.
    glow(Offset(size.width * .95, 0), size.width * .8, const Color(0x2EC8102E));
    glow(Offset(size.width * .05, 0), size.width * .6, const Color(0x14D4AF37));
    // Linee del campo appena accennate in basso.
    final line = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final mid = Offset(size.width / 2, size.height * 1.02);
    canvas.drawCircle(mid, size.width * .28, line);
    canvas.drawLine(
      Offset(0, size.height * .78),
      Offset(size.width, size.height * .78),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
