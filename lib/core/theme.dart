import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colori fissi del club, uguali nei due temi: oggetti "di gioco" come le carte,
/// il campo, il walkout e le parti sempre scure (barre in alto e in basso).
class MilanacColors {
  static const black = Color(0xFF0B0B0C);
  static const ink = Color(0xFF111111);
  static const ivory = Color(0xFFF5F1E6);
  static const ivoryMuted = Color(0xFFC9C3B8);

  /// Oro pieno (pulsanti, contatori) e oro chiaro (testo e icone su nero).
  static const gold = Color(0xFFD6B354);
  static const goldLight = Color(0xFFE8C96A);
  static const goldDeep = Color(0xFF8F6E1C);

  /// Carte speciali nero/oro e blu elettrico (come in gioco).
  static const cardGold = Color(0xFFC9A227);
  static const cardGoldText = Color(0xFFE9C964);
  static const blue = Color(0xFF1E5BFF);

  /// Campo da gioco notturno, con le linee color oro.
  static const pitch = Color(0xFF0F2418);
  static const pitchLine = Color(0x73E8C96A);

  /// Rosso solo per ciò che va fatto con attenzione (uscire, eliminare, assente).
  static const danger = Color(0xFFC8323C);

  /// Superfici scure fisse (barre, fogli sopra al campo, walkout).
  static const surface = Color(0xFF151517);
  static const surfaceHigh = Color(0xFF1E1E21);

  // Nomi della vecchia palette rossonera, ancora usati da alcune schermate: puntano
  // ai colori nero oro più vicini e spariscono man mano che le schermate passano
  // ai colori del tema (context.pal).
  static const red = goldDeep;
  static const redDark = Color(0xFF5E4C1E);
  static const redText = Color(0xFFFF7A82);
}

/// Font sportivo condensato per titoli, numeri e carte.
const sportFont = 'Oswald';

/// Font dei testi, dei pulsanti e degli elenchi.
const bodyFont = 'Barlow';

/// Caratteri della vecchia pergamena del regolamento (spariscono con la nuova lettura).
const serifFont = 'CormorantGaramond';
const scriptFont = 'GreatVibes';

/// I colori che cambiano tra tema scuro (predefinito) e tema chiaro.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceHigher,
    required this.border,
    required this.borderStrong,
    required this.outline,
    required this.divider,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.accentTint,
    required this.accentTintBorder,
    required this.importantBorder,
    required this.chipBorder,
    required this.hero,
    required this.heroBorder,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
  });

  final Brightness brightness;

  /// Sfondo delle schermate, card, campi e superfici più alte.
  final Color bg, surface, surfaceHigh, surfaceHigher;
  final Color border, borderStrong, outline, divider;

  /// Testo principale, secondario, didascalie e voci spente.
  final Color text, textSecondary, textMuted, textDisabled;

  /// Azione principale (oro pieno nel tema scuro, nero nel chiaro) e testo sopra.
  final Color accent, onAccent;

  /// Testo e icone "oro", selezione attiva (scheda, filtro) e il suo bordo.
  final Color accentText, accentTint, accentTintBorder;

  /// Bordo oro delle card importanti e dei filtri selezionati.
  final Color importantBorder, chipBorder;

  /// Card in evidenza (ultimo risultato, intestazioni): testo sempre avorio.
  final Color hero, heroBorder;

  /// Stati: presente, in ritardo, assente (colore del testo e del fondo).
  final Color success, successBg, warning, warningBg, danger, dangerBg;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0B0C),
    surface: Color(0xFF151517),
    surfaceHigh: Color(0xFF1E1E21),
    surfaceHigher: Color(0xFF26262A),
    border: Color(0xFF2B2B2F),
    borderStrong: Color(0xFF3A3A3F),
    outline: Color(0xFF55555B),
    divider: Color(0xFF26262A),
    text: Color(0xFFF5F1E6),
    textSecondary: Color(0xFFC9C3B8),
    textMuted: Color(0xFFA8A29A),
    textDisabled: Color(0xFF8E8982),
    accent: Color(0xFFD6B354),
    onAccent: Color(0xFF111111),
    accentText: Color(0xFFE8C96A),
    accentTint: Color(0xFF2A2312),
    accentTintBorder: Color(0xFF5E4C1E),
    importantBorder: Color(0xFF6B5622),
    chipBorder: Color(0xFF8F7428),
    hero: Color(0xFF1A1710),
    heroBorder: Color(0xFF4A3D18),
    success: Color(0xFF5FD39A),
    successBg: Color(0xFF12301F),
    warning: Color(0xFFF2B65A),
    warningBg: Color(0xFF33260F),
    danger: Color(0xFFFF7A82),
    dangerBg: Color(0xFF3A161A),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF6F4EF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1EEE7),
    surfaceHigher: Color(0xFFE9E5DC),
    border: Color(0xFFE6E1D6),
    borderStrong: Color(0xFFD3CCBE),
    outline: Color(0xFF111111),
    divider: Color(0xFFEFEBE2),
    text: Color(0xFF111111),
    textSecondary: Color(0xFF3F3C37),
    textMuted: Color(0xFF5C5852),
    textDisabled: Color(0xFF8A857D),
    accent: Color(0xFF111111),
    onAccent: Color(0xFFE8C96A),
    accentText: Color(0xFF7A5C0E),
    accentTint: Color(0xFFF3EBD3),
    accentTintBorder: Color(0xFFD9C48A),
    importantBorder: Color(0xFFCDB77A),
    chipBorder: Color(0xFFB8952F),
    hero: Color(0xFF111111),
    heroBorder: Color(0xFF111111),
    success: Color(0xFF0F5E33),
    successBg: Color(0xFFE3F2E9),
    warning: Color(0xFF7A4600),
    warningBg: Color(0xFFFBEFD9),
    danger: Color(0xFF9E0F1A),
    dangerBg: Color(0xFFFBE3E5),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) =>
      other == null || t < .5 ? this : other;
}

extension AppPaletteX on BuildContext {
  /// I colori del tema in uso (scuro o chiaro).
  AppPalette get pal =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

/// Il tema dell'app, scuro (predefinito) o chiaro.
ThemeData buildTheme([Brightness brightness = Brightness.dark]) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.accentTint,
    onPrimaryContainer: p.accentText,
    secondary: p.accentText,
    onSecondary: p.onAccent,
    secondaryContainer: p.accentTint,
    onSecondaryContainer: p.accentText,
    tertiary: MilanacColors.blue,
    onTertiary: Colors.white,
    error: p.danger,
    onError: p.isDark ? MilanacColors.ink : Colors.white,
    errorContainer: p.dangerBg,
    onErrorContainer: p.danger,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceHigh,
    surfaceContainerHighest: p.surfaceHigher,
    outline: p.outline,
    outlineVariant: p.border,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: p.text,
    onInverseSurface: p.bg,
    inversePrimary: p.accentText,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: bodyFont,
  );

  // Titoli in Oswald (pesi 400-700), il resto in Barlow.
  TextStyle? sport(TextStyle? t, {FontWeight weight = FontWeight.w600}) =>
      t?.copyWith(fontFamily: sportFont, fontWeight: weight, letterSpacing: .5);
  final text = base.textTheme.copyWith(
    displayLarge: sport(base.textTheme.displayLarge, weight: FontWeight.w700),
    displayMedium: sport(base.textTheme.displayMedium, weight: FontWeight.w700),
    displaySmall: sport(base.textTheme.displaySmall, weight: FontWeight.w700),
    headlineLarge: sport(base.textTheme.headlineLarge),
    headlineMedium: sport(base.textTheme.headlineMedium),
    headlineSmall: sport(base.textTheme.headlineSmall),
    titleLarge: sport(base.textTheme.titleLarge),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );

  final rounded12 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  const buttonText = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: .2,
  );

  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.divider,
    textTheme: text,
    // Barre in alto: sempre scure, con il nome della sezione in Oswald.
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF151517),
      foregroundColor: MilanacColors.ivory,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontFamily: sportFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: MilanacColors.ivory,
      ),
    ),
    // Barra in basso: sempre scura, scheda attiva con la pillola dorata.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.isDark ? const Color(0xFF151517) : MilanacColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: const Color(0xFF2A2312),
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 24,
          color: s.contains(WidgetState.selected)
              ? MilanacColors.goldLight
              : const Color(0xFFA8A29A),
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: bodyFont,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? MilanacColors.ivory
              : const Color(0xFFA8A29A),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        disabledBackgroundColor: p.surfaceHigh,
        disabledForegroundColor: p.textDisabled,
        minimumSize: const Size(64, 48),
        textStyle: buttonText,
        shape: rounded12,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 0,
        minimumSize: const Size(64, 48),
        textStyle: buttonText,
        shape: rounded12,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: BorderSide(color: p.outline, width: 1.5),
        minimumSize: const Size(64, 48),
        textStyle: buttonText,
        shape: rounded12,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accentText,
        textStyle: buttonText.copyWith(fontSize: 15),
        shape: rounded12,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: buttonText,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHigh,
      labelStyle: TextStyle(color: p.textSecondary),
      hintStyle: TextStyle(color: p.textDisabled),
      helperStyle: TextStyle(color: p.textMuted),
      prefixIconColor: p.textMuted,
      suffixIconColor: p.textMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.borderStrong, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.borderStrong, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.chipBorder, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.danger, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: p.accentTint,
      disabledColor: p.surfaceHigh,
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.selected)
              ? p.chipBorder
              : p.borderStrong,
        ),
      ),
      labelStyle: TextStyle(
        fontFamily: bodyFont,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: p.text,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: bodyFont,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: p.accentText,
      ),
      checkmarkColor: p.accentText,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.surfaceHigh,
        foregroundColor: p.textSecondary,
        selectedBackgroundColor: p.accentTint,
        selectedForegroundColor: p.accentText,
        side: BorderSide(color: p.border),
        textStyle: buttonText.copyWith(fontSize: 14),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.accentText,
      unselectedLabelColor: p.textSecondary,
      indicatorColor: p.accentText,
      dividerColor: Colors.transparent,
      labelStyle: buttonText.copyWith(fontSize: 15),
      unselectedLabelStyle: buttonText.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textMuted,
      textColor: p.text,
      subtitleTextStyle: TextStyle(color: p.textMuted, fontSize: 14),
    ),
    dividerTheme: DividerThemeData(color: p.divider, space: 1, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border),
      ),
      titleTextStyle: TextStyle(
        fontFamily: sportFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: .6,
        color: p.text,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.surface,
      showDragHandle: true,
      dragHandleColor: p.borderStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.isDark ? p.surfaceHigher : MilanacColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        color: MilanacColors.ivory,
      ),
      actionTextColor: MilanacColors.goldLight,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accentText,
      linearTrackColor: p.surfaceHigher,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onAccent : p.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.borderStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : null,
      ),
      checkColor: WidgetStatePropertyAll(p.onAccent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accentText : p.textMuted,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accentText,
      thumbColor: p.accentText,
      inactiveTrackColor: p.surfaceHigher,
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: MilanacColors.gold,
      textColor: MilanacColors.ink,
      textStyle: const TextStyle(
        fontFamily: bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.isDark ? p.surfaceHigher : MilanacColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: MilanacColors.ivory, fontSize: 13),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: p.accentText,
      collapsedIconColor: p.textMuted,
      textColor: p.text,
      collapsedTextColor: p.text,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.surface),
    // Transizioni morbide tra le pagine.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Sfondo delle schermate: il nero del tema (nel chiaro, l'avorio). Resta come
/// contenitore per le pagine che lo usano ancora.
class StadiumBackground extends StatelessWidget {
  const StadiumBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.pal.bg, child: child);
}
