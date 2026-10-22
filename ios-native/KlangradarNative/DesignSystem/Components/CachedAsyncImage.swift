import SwiftUI

/// Drop-in-Ersatz für `AsyncImage(url:) { phase in ... }`, der über
/// `ImageCache` läuft statt bei jeder Sichtbarkeit neu zu laden/dekodieren.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    /// Längste Kante in Pixeln (Standard: 900); kleine Avatare laden kleiner.
    var maxPixel: CGFloat = ImageCache.defaultMaxPixel
    @ViewBuilder var content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    /// Auf feste Stufen runden, damit nicht jede Pixelbreite einen eigenen Cache-Eintrag erzeugt.
    private var bucket: CGFloat {
        [240, 480, 900, 1600].first { CGFloat($0) >= maxPixel } ?? 1600
    }

    var body: some View {
        content(phase)
            .task(id: url?.absoluteString ?? "") {
                guard let url else { phase = .empty; return }
                if let cached = ImageCache.shared.cached(url, maxPixel: bucket) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                phase = .empty
                if let image = await ImageCache.shared.image(for: url, maxPixel: bucket) {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure(URLError(.badServerResponse))
                }
            }
    }
}
