import Foundation

/// Zentrale Anlaufstelle für Links ins Event: Push-Tipp ("route": "/event/<slug>"),
/// Widget/Live Activity (de.klangradar.native://event/<slug>) und Spotlight.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var pendingEventSlug: String?
    /// Freundes-Einladung (de.klangradar.native://friend/<CODE>).
    @Published var pendingFriendCode: String?
    /// Von Siri/Kurzbefehlen (KlangradarShortcuts): Tab bzw. KI öffnen.
    @Published var pendingTab: String?
    @Published var pendingCoach = false
    /// Freunde-Bereich öffnen (Push "/friends" bzw. "/plans").
    @Published var pendingFriendsTab: FriendsHubTab?

    /// true, wenn der Link ein Event-Link war und übernommen wurde.
    @discardableResult
    func handle(url: URL) -> Bool {
        if url.scheme == "de.klangradar.native", url.host == "event" {
            return open(slug: url.lastPathComponent)
        }
        if url.scheme == "de.klangradar.native", url.host == "friend", url.lastPathComponent.count >= 6 {
            pendingFriendCode = url.lastPathComponent.uppercased()
            return true
        }
        if url.host?.hasSuffix("klangradar.com") == true {
            return handle(route: url.path)
        }
        return false
    }

    @discardableResult
    func handle(route: String) -> Bool {
        let parts = route.split(separator: "/")
        // Einladungslink https://klangradar.com/f/<CODE>
        if parts.count == 2, parts[0] == "f", parts[1].count >= 6 {
            pendingFriendCode = parts[1].uppercased()
            return true
        }
        if parts.count == 1, parts[0] == "friends" { pendingFriendsTab = .friends; return true }
        if parts.count == 1, parts[0] == "plans" { pendingFriendsTab = .plans; return true }
        guard parts.count == 2, parts[0] == "event" else { return false }
        return open(slug: String(parts[1]))
    }

    private func open(slug: String) -> Bool {
        guard !slug.isEmpty, slug != "event" else { return false }
        pendingEventSlug = slug
        return true
    }
}
