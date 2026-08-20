import Foundation

/// Stale-while-revalidate-Snapshot des Home-Feeds (Nutzeranfrage Punkt 12,
/// "Offline-/Cache-Layer") — auf Disk statt nur im Speicher, damit ein
/// Kaltstart sofort etwas anzeigen kann, bevor die Netzwerk-Antwort da ist,
/// und die App auch ganz ohne Netz nicht leer bleibt.
struct HomeSnapshot: Codable {
    let events: [ConcertEvent]
    let recommendedEvents: [ConcertEvent]
    let discoveryEvents: [ConcertEvent]
    let popularEvents: [ConcertEvent]
    let newlyAnnouncedEvents: [ConcertEvent]
    let savedAtTimestamp: Double

    var isFresh: Bool {
        Date().timeIntervalSince1970 - savedAtTimestamp < HomeCache.maxAge
    }
}

enum HomeCache {
    /// Nach dieser Zeit gilt ein Snapshot als zu alt, um noch angezeigt zu
    /// werden (verhindert tagealte Ankündigungen/Preise offline).
    static let maxAge: TimeInterval = 12 * 3600

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home_snapshot.json")
    }

    static func load() -> HomeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(HomeSnapshot.self, from: data),
              snapshot.isFresh else { return nil }
        return snapshot
    }

    static func save(_ snapshot: HomeSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
