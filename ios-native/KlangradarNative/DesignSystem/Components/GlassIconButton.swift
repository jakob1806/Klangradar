import SwiftUI

struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                // Das Herz liegt direkt auf dem Konzertbild. Zwei kompakte
                // Schatten halten Kontur und Füllung sowohl auf sehr dunklen
                // als auch auf hellen Fotos lesbar, ohne einen sichtbaren
                // Kreis oder eine eigene Button-Fläche darum zu zeichnen.
                .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1)
                .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
