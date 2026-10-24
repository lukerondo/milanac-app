import 'package:flutter/painting.dart';

import '../../core/theme.dart';
import 'card_stats.dart';

/// Colori fissi delle carte e dei premi: sono oggetti "di gioco", uguali nel tema
/// scuro e in quello chiaro (come le carte in gioco). Stanno tutti qui, non sparsi
/// nelle schermate; il resto dell'interfaccia usa `context.pal`.
abstract final class CardColors {
  /// Nero/oro: fondo, inizio della sfumatura della carta grande, filetti interni e
  /// riga dei dati sotto il nome. Bordo e scritte sono l'oro delle carte del club.
  static const neroOro = Color(0xFF16130A);
  static const neroOroLight = Color(0xFF221C0C);
  static const neroOroLine = Color(0xFF2E2716);
  static const neroOroInfo = Color(0xFFD9C27A);
  static const gold = MilanacColors.cardGold;
  static const goldText = MilanacColors.cardGoldText;

  /// Blu elettrico: fondo, fine della sfumatura, anello delle foto, scritte blu su
  /// fondo scuro e scritte sopra il blu.
  static const blue = MilanacColors.blue;
  static const blueDeep = Color(0xFF0A2C8F);
  static const blueRing = Color(0xFF4D82FF);
  static const blueText = Color(0xFF8FB0FF);
  static const onBlue = Color(0xFFFFFFFF);
  static const onBlueMuted = Color(0xFFD6E2FF);

  /// Carta normale: sempre scura, con il colore del livello sul bordo.
  static const surface = MilanacColors.surface;
  static const surfaceHigh = MilanacColors.surfaceHigh;
  static const border = Color(0xFF2B2B2F);
  static const portrait = Color(0xFF2B2B2F);
  static const text = MilanacColors.ivory;
  static const textMuted = MilanacColors.ivoryMuted;
  static const caption = Color(0xFFA8A29A);

  /// Livelli dell'overall (bronzo, argento, oro, rossonera) e carta senza overall.
  static const empty = Color(0xFF55555B);
  static const bronze = Color(0xFFB0793F);
  static const silver = Color(0xFFC9CED6);
  static const goldTier = MilanacColors.gold;
  static const rossonera = Color(0xFFC8102E);

  /// Oro dei trofei disegnati (riflesso, metallo, ombra, bordo caldo) e la loro base.
  static const metalLight = Color(0xFFFFF1B8);
  static const metal = Color(0xFFD4AF37);
  static const metalDeep = Color(0xFF8A6A12);
  static const metalWarm = Color(0xFFE9C960);
  static const trophyBase = Color(0xFF2B1A12);

  /// Testo e icone di una carta speciale sulle superfici del tema (leggibili anche
  /// nel tema chiaro): l'oro del tema per la nero/oro, il blu per la blu elettrico.
  static Color ink(AppPalette p, {required bool isBlue}) =>
      isBlue ? (p.isDark ? blueText : blue) : p.accentText;

  static Color tier(CardTier t) => switch (t) {
    CardTier.vuota => empty,
    CardTier.bronzo => bronze,
    CardTier.argento => silver,
    CardTier.oro => goldTier,
    CardTier.rossonera => rossonera,
  };
}
