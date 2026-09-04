import SwiftUI

struct LiquidGlassSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat
    private let tint: Color
    private let isInteractive: Bool
    private let content: Content

    init(
        cornerRadius: CGFloat = 24,
        tint: Color = .clear,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(tint)
                        .interactive(isInteractive),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(.ultraThinMaterial)
                // .tint(.clear) auf iOS 26 hat keine sichtbare Wirkung, hier
                // muss der Farbton dagegen manuell als Ebene ergänzt werden —
                // für bestehende Aufrufer mit tint: .clear (Default) ein
                // No-op, für z.B. einen abgedunkelten Kreis über einem Foto
                // (EventDetailView-Kopfzeilenbuttons) auch < iOS 26 wirksam.
                .background(tint)
                .clipShape(.rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(colorScheme == .dark ? .white.opacity(0.22) : .black.opacity(0.09), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}
