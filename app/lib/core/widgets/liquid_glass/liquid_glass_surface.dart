import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Grundbaustein aller Liquid-Glass-Komponenten dieses Projekts —
/// Nutzerauftrag: "Baue das gesamte UI von Klangradar ... zu einem
/// modernen Apple-Liquid-Glass-Design um", Abschnitt 2 ("wiederverwendbare
/// Liquid-Glass-Komponenten"). Jede andere Glass-Komponente in diesem
/// Ordner baut auf dieser einen Fläche auf, damit es keine duplizierten
/// Blur-Implementierungen gibt (Vorgabe Abschnitt 9).
///
/// Das Glas nimmt den Hintergrund bewusst SICHTBAR auf (Blur + dünne
/// farbige Tönung), statt wie reines Milchglas nur weiß-transparent zu
/// wirken (Vorgabe Abschnitt 2). `ClipRRect` begrenzt den `BackdropFilter`
/// immer exakt auf die Kachelgröße — nie ein fullscreen-BackdropFilter
/// (Performance-Vorgabe Abschnitt 2).
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.child,
    super.key,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.glassControl),
    ),
    this.blurSigma = AppGlassDepth.control,
    this.padding,
    this.tintOpacity = 1.0,
    this.showBorder = true,
    this.showHighlight = true,
    this.onImage = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;

  /// Multiplikator auf die Standard-Tönung — z.B. 1.4 für eine "schwerere"
  /// Fläche wie die Navigationsleiste, 0.6 für einen dezenten Chip (Vorgabe:
  /// "dunklere/schwerere Materialien trennen strukturelle Bereiche, hellere
  /// lenken Aufmerksamkeit").
  final double tintOpacity;
  final bool showBorder;
  final bool showHighlight;

  /// true für Glas DIREKT AUF FOTOS (Hero-Overlay, Event-Header) — nutzt
  /// bewusst FESTE dunkle Töne statt der Light/Dark-Theme-Palette. Sonst
  /// läge im Light Mode ein helles Glas mit dem darauf üblichen weißen
  /// Text auf einem Konzertfoto — Kontrast bricht zusammen, unabhängig vom
  /// App-Theme hängt die Lesbarkeit hier vom FOTO ab, nicht vom Theme.
  final bool onImage;

  static const _onImageTint = Color(0x40000000);
  static const _onImageBorder = Color(0x33FFFFFF);
  static const _onImageHighlight = Color(0x26FFFFFF);
  static const _onImageShadow = Color(0x40000000);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reduceTransparency =
        MediaQuery.maybeOf(context)?.disableAnimations ==
        true; // kein eigenes Signal in Flutter-Core für prefers-reduced-transparency

    final baseColor = onImage
        ? _onImageTint
        : (reduceTransparency ? colors.backgroundElevated : colors.glass);
    final borderColor = onImage ? _onImageBorder : colors.glassBorder;
    final highlightColor = onImage ? _onImageHighlight : colors.glassHighlight;
    final shadowColor = onImage ? _onImageShadow : colors.glassShadow;
    final tintColor = onImage ? _onImageTint : colors.glassTint;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: borderRadius,
            border: showBorder
                ? Border.all(color: borderColor, width: 1)
                : null,
            gradient: tintOpacity <= 0
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tintColor.withValues(alpha: tintColor.a * tintOpacity),
                      Colors.transparent,
                    ],
                  ),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              if (showHighlight)
                BoxShadow(
                  color: highlightColor,
                  blurRadius: 0,
                  spreadRadius: -0.6,
                  offset: const Offset(0, 0.6),
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
