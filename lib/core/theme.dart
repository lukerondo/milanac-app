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

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MilanacColors.red,
    brightness: Brightness.dark,
  ).copyWith(
    primary: MilanacColors.red,
    secondary: MilanacColors.gold,
    surface: MilanacColors.surface,
    surfaceContainerHighest: MilanacColors.surfaceHigh,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MilanacColors.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: MilanacColors.black,
      foregroundColor: Colors.white,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Colors.white,
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: MilanacColors.black),
    cardTheme: CardThemeData(
      color: MilanacColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x22FFFFFF)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MilanacColors.red,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
