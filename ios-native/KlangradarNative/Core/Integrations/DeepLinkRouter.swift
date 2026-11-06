import Foundation

/// Zentrale Anlaufstelle für Links ins Event: Push-Tipp ("route": "/event/<slug>"),
/// Widget/Live Activity (de.klangradar.native://event/<slug>) und Spotlight.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var pendingEventSlug: String?
    /// Spielstätte/Person/Ensemble/Werk per Link (02.11.2026):
    /// de.klangradar.native://venue/<slug> bzw. klangradar.com/venue/<slug>.
    @Published var pendingEntity: EntityRoute?
    /// Freundes-Einladung (de.klangradar.native://friend/<CODE>).
    /// Seit 28.10.2026 gespeichert, damit der Code Anmeldung und Onboarding
    /// (auch einen App-Neustart) übersteht; FriendsView übernimmt ihn danach.
    @Published var pendingFriendCode: String? = UserDefaults.standard.string(forKey: DeepLinkRouter.pendingFriendCodeKey) {
        didSet { UserDefaults.standard.set(pendingFriendCode, forKey: Self.pendingFriendCodeKey) }
    }
    nonisolated static let pendingFriendCodeKey = "pendingFriendInviteCode"
    /// Zählt jeden geöffneten Einladungslink (06.11.2026). Wurde derselbe
    /// QR-Code erneut gescannt, änderte sich pendingFriendCode nicht und es
    /// passierte nichts; der Zähler löst trotzdem aus.
    @Published var friendInviteTick = 0
    /// Von Siri/Kurzbefehlen (KlangradarShortcuts): Tab bzw. KI öffnen.
    @Published var pendingTab: String?
    @Published var pendingCoach = false
    /// Schnellaktion "Freunde fragen" aus einer Mitteilung: auf der
    /// Konzertseite direkt den Planungsdialog öffnen.
    @Published var pendingPlanForSlug: String?
    /// Freunde-Bereich öffnen (Push "/friends" bzw. "/plans").
    @Published var pendingFriendsTab: FriendsHubTab?
    /// Live-Aktivität „Ticket“ (06.11.2026): de.klangradar.native://ticket/<slug>.
    @Published var pendingTicketSlug: String?

    /// true, wenn der Link ein Event-Link war und übernommen wurde.
    @discardableResult
    func handle(url: URL) -> Bool {
        if url.scheme == "de.klangradar.native", url.host == "ticket", !url.lastPathComponent.isEmpty {
            pendingTicketSlug = url.lastPathComponent
            return true
        }
        if url.scheme == "de.klangradar.native", url.host == "event" {
            return open(slug: url.lastPathComponent)
        }
        if url.scheme == "de.klangradar.native", let host = url.host, url.path.isEmpty || url.path == "/",
           ["coach", "calendar", "search", "map"].contains(host) {
            return handle(route: "/\(host)")
        }
        if url.scheme == "de.klangradar.native", let host = url.host, let kind = EntityKind(rawValue: host),
           !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" {
            pendingEntity = EntityRoute(kind: kind, identifier: url.lastPathComponent)
            return true
        }
        if url.scheme == "de.klangradar.native", url.host == "friend", url.lastPathComponent.count >= 6 {
            pendingFriendCode = url.lastPathComponent.uppercased()
            friendInviteTick += 1
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
            friendInviteTick += 1
            return true
        }
        if parts.count == 1, parts[0] == "friends" { pendingFriendsTab = .friends; return true }
        // Kontrollzentrum/Aktionstaste (02.11.2026).
        if parts.count == 1, parts[0] == "coach" { pendingCoach = true; return true }
        if parts.count == 1, ["calendar", "search", "map"].contains(String(parts[0])) { pendingTab = String(parts[0]); return true }
        if parts.count == 1, parts[0] == "plans" { pendingFriendsTab = .plans; return true }
        if parts.count == 2, let kind = EntityKind(rawValue: String(parts[0])) {
            pendingEntity = EntityRoute(kind: kind, identifier: String(parts[1]))
            return true
        }
        // Konzertlinks aus E-Mails: https://klangradar.com/e/<slug>
        guard parts.count == 2, parts[0] == "event" || parts[0] == "e" else { return false }
        return open(slug: String(parts[1]))
    }

    private func open(slug: String) -> Bool {
        guard !slug.isEmpty, slug != "event" else { return false }
        pendingEventSlug = slug
        return true
    }
}
