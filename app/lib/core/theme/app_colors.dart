import 'package:flutter/material.dart';

/// Design-Tokens — Apple-Liquid-Glass-Umbau (Nutzerauftrag: "Baue das
/// gesamte UI von Klangradar ... zu einem modernen Apple-Liquid-Glass-Design
/// um", Referenzen app/design/ui-redesign-mockups/03-apple-liquid-glass.png
/// + 06-native-apple-ios.png). Löst die bisherige rot-goldene Palette durch
/// eine kühle Blau/Petrol-Welt ab — beide Modi bewusst eigenständig
/// gestaltet statt automatisch invertiert, wie schon in der Vorgänger-
/// Palette. Neue glass*-Felder ergänzen die bestehenden Farbrollen additiv,
/// damit kein bestehender Aufrufer bricht.
class AppColors {
  const AppColors._();

  static const light = AppColorPalette(
    backgroundPrimary: Color(0xFFF4F7FA), // warmes Eisweiß/helles Blaugrau
    backgroundSecondary: Color(0xFFFFFFFF),
    backgroundElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF12161C), // fast schwarz, minimal blau unterlegt
    textSecondary: Color(0xFF5B6572),
    textTertiary: Color(0xFF737E8B),
    accentPrimary: Color(0xFF0A6E8C), // kühles Petrol/Blau
    accentSecondary: Color(0xFF3B8FA8),
    separator: Color(0xFFDEE4EA),
    success: Color(0xFF2E7D46),
    warning: Color(0xFFA9700A),
    error: Color(0xFFB23A3A),
    glass: Color(0xB8FAFCFE),
    glassTint: Color(0x1F0A6E8C),
    glassBorder: Color(0x33FFFFFF),
    glassHighlight: Color(0x99FFFFFF),
    glassShadow: Color(0x1A0A1420),
  );

  static const dark = AppColorPalette(
    backgroundPrimary: Color(0xFF080C14), // tiefes Marineblau
    backgroundSecondary: Color(0xFF11161F),
    backgroundElevated: Color(0xFF1A2029),
    textPrimary: Color(0xFFF3F6F9),
    textSecondary: Color(0xFF9AA6B4),
    textTertiary: Color(0xFF7E8996),
    accentPrimary: Color(0xFF3FB8DE), // leuchtendes, nicht neonhaftes Blau
    accentSecondary: Color(0xFF6FCBE8),
    separator: Color(0xFF262E3A),
    success: Color(0xFF4FBE71),
    warning: Color(0xFFE8A33D),
    error: Color(0xFFE3685F),
    glass: Color(0xB80D131D),
    glassTint: Color(0x263FB8DE),
    glassBorder: Color(0x2AFFFFFF),
    glassHighlight: Color(0x40FFFFFF),
    glassShadow: Color(0x66000000),
  );
}

class AppColorPalette {
  const AppColorPalette({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.backgroundElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.separator,
    required this.success,
    required this.warning,
    required this.error,
    required this.glass,
    required this.glassTint,
    required this.glassBorder,
    required this.glassHighlight,
    required this.glassShadow,
  });

  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color backgroundElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color separator;
  final Color success;
  final Color warning;
  final Color error;

  /// Halbtransparenter Fond für großflächige Glass-Container (Navigationsleiste).
  final Color glass;

  /// Farbige Tönung dünn über dem Blur, damit das Glas den Hintergrund
  /// sichtbar aufnimmt statt wie reines Milchglas zu wirken.
  final Color glassTint;

  /// Feine helle Kontur um Glasflächen (1px).
  final Color glassBorder;

  /// Kontrollierter Highlight-Akzent (z.B. oberer Rand/Glanzkante).
  final Color glassHighlight;
  final Color glassShadow;
}

/// ThemeExtension, damit die vollen Design-Tokens (nicht nur die von
/// Material's ColorScheme abgedeckten Rollen) per `Theme.of(context)` erreichbar sind.
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension(this.palette);

  final AppColorPalette palette;

  @override
  AppColorsExtension copyWith() => this;

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return t < 0.5 ? this : other;
  }

  Color get backgroundPrimary => palette.backgroundPrimary;
  Color get backgroundSecondary => palette.backgroundSecondary;
  Color get backgroundElevated => palette.backgroundElevated;
  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get textTertiary => palette.textTertiary;
  Color get accentPrimary => palette.accentPrimary;
  Color get accentSecondary => palette.accentSecondary;
  Color get separator => palette.separator;
  Color get success => palette.success;
  Color get warning => palette.warning;
  Color get error => palette.error;
  Color get glass => palette.glass;
  Color get glassTint => palette.glassTint;
  Color get glassBorder => palette.glassBorder;
  Color get glassHighlight => palette.glassHighlight;
  Color get glassShadow => palette.glassShadow;
}

extension AppThemeContext on BuildContext {
  AppColorsExtension get appColors =>
      Theme.of(this).extension<AppColorsExtension>()!;
}
