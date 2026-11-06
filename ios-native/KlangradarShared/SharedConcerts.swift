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

/// Kleines Konzertbild für die Live-Aktivität (06.11.2026). Live-Aktivitäten
/// dürfen nichts aus dem Netz laden; die App legt das Bild deshalb verkleinert
/// in der App-Gruppe ab, die Widget-Erweiterung liest es von dort.
enum SharedActivityImageStore {
    static func url(forSlug slug: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConcertStore.appGroup)?
            .appendingPathComponent("activity-\(slug.replacingOccurrences(of: "/", with: "_")).jpg")
    }
    static func data(forSlug slug: String) -> Data? {
        url(forSlug: slug).flatMap { try? Data(contentsOf: $0) }
    }
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

/// Erstellt von Claude Code (26.10.2026): Sitzplatz je Konzert, nur lokal
/// (App Group), damit Live Activity und Widget ihn anzeigen können.
struct ConcertSeat: Codable, Hashable, Sendable {
    var entrance = ""
    var block = ""
    var row = ""
    var seat = ""

    var isEmpty: Bool { [entrance, block, row, seat].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// z. B. "Block A · Reihe 5 · Platz 12"
    var summary: String {
        [entrance.isEmpty ? nil : "Eingang \(entrance)", block.isEmpty ? nil : "Block \(block)",
         row.isEmpty ? nil : "Reihe \(row)", seat.isEmpty ? nil : "Platz \(seat)"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

enum SharedSeatStore {
    private static func key(_ slug: String) -> String { "seat.\(slug)" }

    static func seat(forSlug slug: String) -> ConcertSeat? {
        guard let data = UserDefaults(suiteName: SharedConcertStore.appGroup)?.data(forKey: key(slug)),
              let seat = try? JSONDecoder().decode(ConcertSeat.self, from: data), !seat.isEmpty else { return nil }
        return seat
    }

    static func save(_ seat: ConcertSeat, forSlug slug: String) {
        let defaults = UserDefaults(suiteName: SharedConcertStore.appGroup)
        if seat.isEmpty { defaults?.removeObject(forKey: key(slug)); return }
        defaults?.set(try? JSONEncoder().encode(seat), forKey: key(slug))
    }
}

#if canImport(ActivityKit)
/// Live Activity am Konzerttag: Sperrbildschirm und Dynamic Island.
struct ConcertActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String // "upcoming" | "doors" | "running"
        /// Empfohlene Losgeh-Zeit vom aktuellen Standort (nil = unbekannt).
        var leaveAt: Date? = nil
        /// z. B. "17 Min. mit ÖPNV"
        var travel: String? = nil
        /// Geschätzter Pausenbeginn, falls bekannt.
        var pauseAt: Date? = nil
    }
    let slug: String
    let title: String
    let venue: String
    let start: Date
}
#endif
