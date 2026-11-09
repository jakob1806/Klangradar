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

/// Erstellt von Claude Code (26.10.2026): Sitzplatz je Konzert, nur lokal
/// (App Group), damit Live Activity und Widget ihn anzeigen können.
struct ConcertSeat: Codable, Hashable, Sendable {
    var entrance = ""
    var block = ""
    var row = ""
    var seat = ""
    /// 09.11.2026: Bezeichnungen wie auf dem Ticket („Tür“, „Rang“, „Sitz“)
    /// und weitere Angaben (Etage, Kategorie …). Leer = Standardbezeichnung.
    var entranceLabel = ""
    var blockLabel = ""
    var rowLabel = ""
    var seatLabel = ""
    var extras: [SeatExtra] = []

    struct SeatExtra: Codable, Hashable, Sendable, Identifiable {
        var id = UUID()
        var label: String
        var value: String
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entrance = try c.decodeIfPresent(String.self, forKey: .entrance) ?? ""
        block = try c.decodeIfPresent(String.self, forKey: .block) ?? ""
        row = try c.decodeIfPresent(String.self, forKey: .row) ?? ""
        seat = try c.decodeIfPresent(String.self, forKey: .seat) ?? ""
        entranceLabel = try c.decodeIfPresent(String.self, forKey: .entranceLabel) ?? ""
        blockLabel = try c.decodeIfPresent(String.self, forKey: .blockLabel) ?? ""
        rowLabel = try c.decodeIfPresent(String.self, forKey: .rowLabel) ?? ""
        seatLabel = try c.decodeIfPresent(String.self, forKey: .seatLabel) ?? ""
        extras = try c.decodeIfPresent([SeatExtra].self, forKey: .extras) ?? []
    }

    static let defaultLabels = (entrance: "Eingang", block: "Block", row: "Reihe", seat: "Platz")

    /// Alle ausgefüllten Angaben in Ticket-Reihenfolge: (Bezeichnung, Wert).
    var parts: [(label: String, value: String)] {
        func lbl(_ custom: String, _ fallback: String) -> String {
            let t = custom.trimmingCharacters(in: .whitespaces); return t.isEmpty ? fallback : t
        }
        let core: [(String, String)] = [
            (lbl(blockLabel, Self.defaultLabels.block), block), (lbl(rowLabel, Self.defaultLabels.row), row),
            (lbl(seatLabel, Self.defaultLabels.seat), seat), (lbl(entranceLabel, Self.defaultLabels.entrance), entrance)
        ]
        return (core + extras.map { ($0.label, $0.value) })
            .map { ($0.0, $0.1.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.1.isEmpty }
            .map { (label: $0.0, value: $0.1) }
    }

    var isEmpty: Bool { parts.isEmpty }

    /// z. B. "Rang Mitte · Reihe 1 · Sitz 7 · Tür M · 2. OG"
    var summary: String {
        parts.map { $0.label == "Bereich" || $0.label.isEmpty ? $0.value : "\($0.label) \($0.value)" }
            .joined(separator: " · ")
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
        /// 06.11.2026: Einlass, Pausenende, Ende (jeweils ggf. geschätzt).
        var doorsAt: Date? = nil
        var doorsEstimated: Bool? = nil
        var pauseEndAt: Date? = nil
        var endAt: Date? = nil
        var endEstimated: Bool? = nil
        /// Vom Server (06.11.2026): geänderte Beginnzeit und Hinweis wie
        /// „Die Veranstaltung wurde abgesagt.“ oder eine Umbesetzung.
        var startAt: Date? = nil
        var notice: String? = nil
        /// 07.11.2026: Programm für „Jetzt läuft“ – Kurztitel und Dauer (Min.).
        var programTitles: [String]? = nil
        var programMinutes: [Int]? = nil
    }
    let slug: String
    let title: String
    let venue: String
    let start: Date
}
#endif
