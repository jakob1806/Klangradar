import SwiftUI

/// Nutzerfeedback (Verlauf, per Screenshot-Vergleich): das komplette
/// Abschalten des automatischen Scroll-Edge-Effekts (frühere Fassung dieser
/// Datei: .toolbarBackgroundVisibility(.hidden) + .scrollEdgeEffectHidden)
/// ging zu weit — dadurch wurde die Titelleiste komplett durchsichtig,
/// Statuszeile/Titel und darunterliegender Inhalt überlagerten sich
/// unleserlich. Danach .soft probiert (kantenloser Übergang), aber laut
/// Nutzerfeedback war der Blur damit "zu kurz"/endet zu spät -- .soft hat
/// offenbar eine kürzere Ausdehnung als .automatic. SwiftUI bietet keinen
/// eigenen Parameter für die Ausdehnung/Länge des Effekts (siehe
/// ScrollEdgeEffectStyle im SDK-Interface: nur .automatic/.hard/.soft/
/// hidden) -- .automatic ist Apples eigener, in Systemapps verwendeter
/// Standardwert und damit die einzige Stellschraube dafür.
struct HiddenScrollEdgeNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.automatic, for: .top)
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
