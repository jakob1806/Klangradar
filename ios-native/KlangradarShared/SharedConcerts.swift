import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Von App und Widget-Extension gemeinsam genutzt (App Group). Die App
/// schreibt die nächsten gemerkten Konzerte, das Widget liest sie.
struct SharedConcert: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let slug: String
    let title: String
    let venue: String
    let start: Date

    var deepLink: URL { URL(string: "de.klangradar.native://event/\(slug)")! }
}

enum SharedConcertStore {
    static let appGroup = "group.de.klangradar.native"
    private static let key = "upcomingFavoriteConcerts"

    static func save(_ concerts: [SharedConcert]) {
        guard let defaults = UserDefaults(suiteName: appGroup), let data = try? JSONEncoder().encode(concerts) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> [SharedConcert] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let concerts = try? JSONDecoder().decode([SharedConcert].self, from: data) else { return [] }
        return concerts.filter { $0.start.addingTimeInterval(3 * 3600) > .now }.sorted { $0.start < $1.start }
    }
}

#if canImport(ActivityKit)
/// Live Activity am Konzerttag: Sperrbildschirm und Dynamic Island.
struct ConcertActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String // "upcoming" | "doors" | "running"
    }
    let slug: String
    let title: String
    let venue: String
    let start: Date
}
#endif
