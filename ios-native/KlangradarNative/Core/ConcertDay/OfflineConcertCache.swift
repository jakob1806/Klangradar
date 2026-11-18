// Erstellt von Claude Code (18.11.2026): Konzerttag offline – die Detaildaten
// (Programm, Besetzung, Spielstätte, Einlass) gemerkter oder geplanter
// Konzerte der nächsten Tage werden lokal gespeichert. Ohne Netz im Saal
// zeigt die Konzertseite den gespeicherten Stand. Ticket, Codes und Platz
// liegen ohnehin schon auf dem Gerät (TicketStore, SharedSeatStore).
import Foundation

enum OfflineConcertCache {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("OfflineConcerts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(_ slug: String) -> URL {
        folder.appendingPathComponent(slug.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    /// Nur Konzerte der nächsten 3 Tage (bis 6 Std. nach Beginn).
    static func shouldKeep(start: Date?) -> Bool {
        guard let start else { return false }
        let delta = start.timeIntervalSinceNow
        return delta > -6 * 3600 && delta < 3 * 86_400
    }

    static func save(_ detail: JSONObject, slug: String) {
        guard let data = try? JSONEncoder().encode(detail) else { return }
        try? data.write(to: file(slug), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cleanUp()
    }

    static func load(slug: String) -> JSONObject? {
        guard let data = try? Data(contentsOf: file(slug)) else { return nil }
        return try? JSONDecoder().decode(JSONObject.self, from: data)
    }

    /// Alte Einträge (älter als 4 Tage) entfernen.
    private static func cleanUp() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date < .now.addingTimeInterval(-4 * 86_400) { try? FileManager.default.removeItem(at: url) }
        }
    }
}
