import SwiftUI

/// Nutzerfeedback (Verlauf, per Screenshot-Vergleich): das komplette
/// Abschalten des automatischen Scroll-Edge-Effekts (frühere Fassung dieser
/// Datei: .toolbarBackgroundVisibility(.hidden) + .scrollEdgeEffectHidden)
/// ging zu weit — dadurch wurde die Titelleiste komplett durchsichtig,
/// Statuszeile/Titel und darunterliegender Inhalt überlagerten sich
/// unleserlich. Der Blur-Effekt soll bleiben (er trennt Titel/Chip lesbar
/// vom scrollenden Inhalt), nur OHNE die zuvor sichtbare harte Kante
/// zwischen Titelleiste und Hintergrund. .soft (statt .automatic/.hard)
/// ist genau dafür gedacht: ein weicher, kantenloser Übergang statt eines
/// abrupt endenden Blur-Streifens.
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
