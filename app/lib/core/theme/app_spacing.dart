/// 8pt-Grid aus docs/04-design-system.md.
class AppSpacing {
  const AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const huge = 64.0;

  static const screenPaddingMobile = 16.0;
  static const screenPaddingTablet = 24.0;
  static const sectionGap = 32.0;
  static const cardGap = 16.0;
}

/// Radien aus docs/04-design-system.md.
class AppRadius {
  const AppRadius._();

  static const card = 20.0;
  static const button = 14.0;
  static const bottomSheet = 28.0;
  static const cardImage = 16.0;

  // Liquid-Glass-Ergänzungen: eigene, aber an die bestehende Skala
  // angelehnte Werte statt neuer beliebiger Zahlen (Nutzervorgabe: "nicht
  // jede Komponente als Pill gestalten", "konsistente Radien").
  static const glassControl = 16.0;
  static const glassCapsule = 999.0;
}

/// Blur-/Tiefen-Stufen für Liquid-Glass-Flächen — je größer die Fläche,
/// desto stärker Blur/Schatten (Skill-Referenz: "Bigger surfaces read as
/// thicker: stronger blur + deeper shadow than small chips").
class AppGlassDepth {
  const AppGlassDepth._();

  static const chip = 12.0;
  static const control = 20.0;
  static const navigation = 28.0;
  static const sheet = 36.0;
}
