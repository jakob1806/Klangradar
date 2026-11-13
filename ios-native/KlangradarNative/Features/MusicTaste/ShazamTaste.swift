// Erstellt von Claude Code (13.11.2026): Shazam im Musikgeschmack.
// Apple lässt Apps den bestehenden Shazam-Verlauf nicht lesen; deshalb
// erkennt Klangradar Musik selbst (ShazamKit, Mikrofon nur auf Tipp).
// Erkannte Titel landen im Musikgeschmack (zusammengeführt, nicht ersetzt)
// und zusätzlich in der Shazam-Mediathek des Nutzers.
import Foundation
import ShazamKit

struct ShazamFind: Codable, Identifiable, Hashable, Sendable {
    var id: String { title + "|" + artist }
    let title: String
    let artist: String
    let date: Date
}

@MainActor
final class ShazamTaste: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var finds: [ShazamFind] = []
    private var session: SHManagedSession?
    private static let key = "shazamFinds"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([ShazamFind].self, from: data) { finds = saved }
    }

    /// Hört bis zu ~12 Sekunden zu und liefert den Treffer (oder nil).
    func recognize() async -> ShazamFind? {
        let session = SHManagedSession()
        self.session = session
        isListening = true
        defer { isListening = false; self.session = nil }
        await session.prepare()
        // Nach 14 Sekunden abbrechen (dann kommt .error zurück → kein Treffer).
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(14))
            session.cancel()
        }
        let result = await session.result()
        timeout.cancel()
        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first, let title = item.title else { return nil }
            let find = ShazamFind(title: title, artist: item.artist ?? "", date: .now)
            finds.removeAll { $0.id == find.id }
            finds.insert(find, at: 0)
            finds = Array(finds.prefix(100))
            if let data = try? JSONEncoder().encode(finds) { UserDefaults.standard.set(data, forKey: Self.key) }
            try? await SHLibrary.default.addItems([item])
            return find
        case .noMatch:
            return nil
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }

    func cancel() { session?.cancel() }

    /// Ein Treffer als Hördaten für den Abgleich.
    static func listening(for find: ShazamFind) -> (artists: [ListenedArtist], tracks: [ListenedTrack]) {
        let artists = find.artist.isEmpty ? [] : [ListenedArtist(name: find.artist, weight: 2, genres: [])]
        return (artists, [ListenedTrack(title: find.title, artist: find.artist, composer: nil, weight: 2)])
    }
}
