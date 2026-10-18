import SwiftUI

/// Kleiner Preis-Hinweis ("ab 25 €", "Eintritt frei", "Ermäßigt") im Stil
/// des "Anzeige"-Labels — dezent, Glas-Material, unten links in Kacheln.
struct PriceBadge: View {
    let event: ConcertEvent

    var body: some View {
        if let label = text {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial.opacity(0.9), in: .capsule)
                .environment(\.colorScheme, .dark)
                .padding(7)
                .accessibilityLabel(label)
        }
    }

    private var text: String? {
        switch (event.priceLabel, event.hasDiscount) {
        case let (price?, true): "\(price) · ermäßigt"
        case let (price?, false): price
        case (nil, true): "Ermäßigt"
        default: nil
        }
    }
}
