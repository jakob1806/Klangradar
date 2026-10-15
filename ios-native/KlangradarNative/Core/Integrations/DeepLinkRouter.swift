import Foundation

/// Zentrale Anlaufstelle für Links ins Event: Push-Tipp ("route": "/event/<slug>"),
/// Widget/Live Activity (de.klangradar.native://event/<slug>) und Spotlight.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var pendingEventSlug: String?

    /// true, wenn der Link ein Event-Link war und übernommen wurde.
    @discardableResult
    func handle(url: URL) -> Bool {
        if url.scheme == "de.klangradar.native", url.host == "event" {
            return open(slug: url.lastPathComponent)
        }
        if url.host?.hasSuffix("klangradar.com") == true {
            return handle(route: url.path)
        }
        return false
    }

    @discardableResult
    func handle(route: String) -> Bool {
        let parts = route.split(separator: "/")
        guard parts.count == 2, parts[0] == "event" else { return false }
        return open(slug: String(parts[1]))
    }

    private func open(slug: String) -> Bool {
        guard !slug.isEmpty, slug != "event" else { return false }
        pendingEventSlug = slug
        return true
    }
}
