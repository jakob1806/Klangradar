import SwiftUI

/// Nutzerfeedback: Home/Suche/Kalender zeigten weiterhin einen sichtbaren
/// Blur-Streifen zwischen Hintergrund und Titelleiste, obwohl kein
/// ToolbarItem mehr doppeltes Glas zeigte. Grund: iOS 26 blendet an
/// Titelleisten automatisch einen eigenen "Scroll Edge Effect" ein, sobald
/// Inhalt darunter scrollt — unabhängig von .sharedBackgroundVisibility
/// (das nur einzelne ToolbarItems betrifft) und unabhängig vom älteren
/// .toolbarBackground(.hidden) (das dafür bereits als iOS-17-Fallback
/// gesetzt ist). .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
/// ist die iOS-26-Entsprechung, die genau diesen automatischen Rand
/// unterdrückt.
struct HiddenScrollEdgeNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                // Nutzerfeedback (per Screenshot mit Markierung): der Rand
                // blieb trotz .toolbarBackgroundVisibility(.hidden) sichtbar
                // — das ist ein GESONDERTER Mechanismus: iOS 26 blendet am
                // oberen Rand von scrollbarem Inhalt automatisch einen
                // eigenen "Scroll Edge Effect" (Weichzeichner/Fade) ein,
                // unabhängig vom Titelleisten-Hintergrund selbst.
                // scrollEdgeEffectHidden(_:for:) ist die dafür vorgesehene,
                // direkte Abschaltung.
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
