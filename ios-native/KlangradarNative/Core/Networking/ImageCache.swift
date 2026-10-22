import ImageIO
import UIKit

/// Bildcache für alle Fotos der App (CachedAsyncImage, CroppedAsyncImage).
///
/// Nutzerfeedback: In der Suche ("Alles entdecken") brauchten Bilder von
/// Personen, Ensembles, Orten und Werken ewig. Ursachen und Abhilfe:
/// - Speicher: `NSCache` mit verkleinerten Bildern, damit Zurückscrollen
///   sofort ein Bild zeigt (vorher: CroppedAsyncImage ganz ohne Cache).
/// - Festplatte: eigener `URLCache` (200 MB) mit Revalidierung statt
///   erzwungenem Neuladen. Geänderte Bilder unter gleicher URL kommen über
///   ETag/Last-Modified trotzdem an (Grund des früheren Neulade-Fixes).
/// - Größe: Wikimedia-Originale (oft mehrere MB) werden als Vorschaubild
///   in passender Breite geladen und per ImageIO verkleinert dekodiert.
/// - Gleichzeitige Anfragen für dieselbe URL teilen sich einen Download.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 120 * 1024 * 1024
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "klangradar-images")
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    /// Längste Bildkante in Pixeln, auf die verkleinert dekodiert wird.
    static let defaultMaxPixel: CGFloat = 900

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixel))" as NSString
    }

    /// Synchroner Treffer, damit ein bereits geladenes Bild ohne Flackern erscheint.
    func cached(_ url: URL, maxPixel: CGFloat = ImageCache.defaultMaxPixel) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func image(for url: URL, maxPixel: CGFloat = ImageCache.defaultMaxPixel) async -> UIImage? {
        let cacheKey = key(url, maxPixel)
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let session = self.session
        let task: Task<UIImage?, Never> = lock.withLock {
            if let running = inFlight[cacheKey as String] { return running }
            let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
                let source = Self.sizedURL(url, maxPixel: maxPixel)
                if let (data, response) = try? await session.data(from: source),
                   (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false {
                    return Self.downsample(data, maxPixel: maxPixel)
                }
                // Wikimedia-Vorschau fehlgeschlagen: Original versuchen.
                guard source != url, let (data, _) = try? await session.data(from: url) else { return nil }
                return Self.downsample(data, maxPixel: maxPixel)
            }
            inFlight[cacheKey as String] = task
            return task
        }

        let image = await task.value
        lock.withLock { inFlight[cacheKey as String] = nil }
        if let image {
            cache.setObject(image, forKey: cacheKey, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }
        return image
    }

    /// Dekodiert direkt in Zielgröße (spart Speicher und Rechenzeit gegenüber UIImage(data:)).
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return UIImage(data: data) }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return UIImage(data: data) }
        return UIImage(cgImage: cgImage)
    }

    /// upload.wikimedia.org/…/commons/a/ab/Datei.jpg → …/commons/thumb/a/ab/Datei.jpg/<breite>px-Datei.jpg
    /// Supabase-Bildtransformation (`/render/image`, 5–7x kleinere Dateien).
    /// Kostet bei Supabase extra (Abrechnung pro Originalbild), daher erst
    /// nach Freigabe durch Jakob einschalten.
    static let usesSupabaseTransforms = false

    static func sizedURL(_ url: URL, maxPixel: CGFloat) -> URL {
        if usesSupabaseTransforms, url.host?.hasSuffix(".supabase.co") == true, url.path.contains("/storage/v1/object/public/"),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.path = url.path.replacingOccurrences(of: "/storage/v1/object/public/", with: "/storage/v1/render/image/public/")
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "width", value: String(Int(min(maxPixel, 1600)))),
                URLQueryItem(name: "quality", value: "75")
            ]
            return components.url ?? url
        }
        guard url.host == "upload.wikimedia.org" else { return url }
        var parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // Erwartet: wikipedia/<projekt>/<x>/<xy>/<Datei>
        guard parts.count == 5, parts[0] == "wikipedia", parts[2] != "thumb",
              let file = parts.last, !file.lowercased().hasSuffix(".svg") else { return url }
        let width = [320, 640, 960, 1280].first { CGFloat($0) >= maxPixel } ?? 1280
        parts.insert("thumb", at: 2)
        parts.append("\(width)px-\(file)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/" + parts.joined(separator: "/")
        return components?.url ?? url
    }
}
