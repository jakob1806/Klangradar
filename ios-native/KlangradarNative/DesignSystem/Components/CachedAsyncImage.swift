import SwiftUI

/// Drop-in-Ersatz für `AsyncImage(url:) { phase in ... }`, der über
/// `ImageCache` läuft statt bei jeder Sichtbarkeit neu zu laden/dekodieren.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else { phase = .empty; return }
                if let cached = ImageCache.shared.cached(url) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                phase = .empty
                if let image = await ImageCache.shared.image(for: url) {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure(URLError(.badServerResponse))
                }
            }
    }
}
