import SwiftUI

/// Nutzerfeedback-Verlauf, per Screenshot-Vergleich, hin und her zwischen
/// den beiden verfügbaren Stilen (SwiftUI bietet nur .automatic/.hard/
/// .soft/hidden, keinen eigenen Längenparameter, siehe ScrollEdgeEffectStyle
/// im SDK-Interface):
/// - Komplettes Abschalten ging zu weit — Titelleiste komplett durchsichtig,
///   Titel/Inhalt überlagerten sich unleserlich.
/// - .automatic hat eine längere Ausdehnung, aber eine sichtbare harte
///   Kante zum Hintergrund.
/// - .soft ist kantenlos, dafür kürzer.
/// Auf ausdrücklichen Nutzerwunsch ("kann diese Kante unsichtbar werden?")
/// hier zugunsten von .soft entschieden — kantenlos schlägt Länge.
struct HiddenScrollEdgeNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            // iOS 17–25 kennen den automatischen Scroll-Edge-Effekt nicht;
            // dort bleibt das ältere .toolbarBackground(.hidden) als
            // Material-Fallback nötig, sonst zeigt die Titelleiste dort ein
            // undurchsichtiges Standardmaterial ohne den eigenen
            // LiquidGlassSurface-Chip darunter durchscheinen zu lassen.
            content.toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
