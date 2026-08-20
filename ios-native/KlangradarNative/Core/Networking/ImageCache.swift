import UIKit

/// In-Memory-Bildcache für AsyncImage-Ersatz. `AsyncImage` selbst cacht
/// nichts über Sichtbarkeitswechsel hinweg — jedes Verlassen und
/// Zurückscrollen zu einer Karte lädt und dekodiert dasselbe Bild erneut
/// (Perf-Audit: Hauptursache für Ruckeln in Rails/Karussells). `NSCache` ist
/// laut Apple-Dokumentation threadsicher, daher genügt eine einfache Klasse
/// ohne Actor-Isolation.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    /// Synchroner Treffer, damit CachedAsyncImage ein bereits geladenes Bild
    /// ohne Zwischenzustand (kein Flackern auf .empty) direkt anzeigen kann.
    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cached(url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
